From iris.algebra Require Import auth excl gset numbers.
From iris.base_logic.lib Require Export invariants.
From iris.heap_lang Require Import lang proofmode notation.

(* ################################################################# *)
(** * Case Study: Ticket Lock *)

(* ================================================================= *)
(** ** Implementation *)

(**
  Let us look at another implementation of a lock, namely a ticket lock.
  Instead of having every thread fight to acquire the lock, the ticket
  lock makes them wait in line. It functions similarly to a ticketing
  system that one often finds in bakeries and pharmacies. Upon entering
  the shop, you pick a ticket with some number and wait until the number
  on the screen has reached your number. Once this happens, it becomes
  your turn to speak to the shop assistant. In our scenario, talking to
  the shop assistant corresponds to accessing the protected resources.

  To implement this, we will maintain two counters: [o] and [n]. The
  first counter, [o], represents the number on the screen – the customer
  currently being served. The second counter, [n], represents the next
  number to be dispensed by the ticketing machine.

  To acquire the lock, a thread must increment the second counter, [n],
  and keep its previous value as a ticket for a position in the queue.
  Once the ticket has been obtained, the thread must wait until the
  first counter, [o], reaches its ticket value. Once this happens, the
  thread gets access to the protected resources. The thread can then
  release the lock by incrementing the first counter.
*)

Definition mk_lock : val :=
  λ: <>, (ref #0, ref #0).

Definition wait : val :=
  rec: "wait" "n" "l" :=
  let: "o" := !(Fst "l") in
  if: "o" = "n" then #() else "wait" "n" "l".

Definition acquire : val :=
  rec: "acquire" "l" :=
  let: "n" := !(Snd "l") in
  if: CAS (Snd "l") "n" ("n" + #1) then
    wait "n" "l"
  else
    "acquire" "l".

Definition release : val :=
  λ: "l", Fst "l" <- ! (Fst "l") + #1.

(* ================================================================= *)
(** ** Representation Predicates *)

(**
  As a ticket lock is a lock, we expect it to satisfy the same
  specification as the spin-lock. This time, you have to come up with
  the necessary resource algebra and lock invariant by yourself. It
  might be instructive to first look through all required predicates and
  specifications to figure out exactly what needs to be proven.
*)

Definition RA : cmra
(* BEGIN SOLUTION *)
  (**
    We will use a finite set of numbers to represent the tickets that
    have been issued – the second counter. This becomes a camera by
    using the disjoint union as an operation.

    For the first counter, we will use the exclusive camera over the
    natural numbers – this means that there can be only one
    access-granting ticket owned at a time.

    By wrapping them both in an authoritative camera, we can use the
    authoritative fragment to bind the values of our counters to the
    ghost state.
  *)
  := authR (prodUR (optionUR (exclR natO)) (gset_disjR nat)).
(* END SOLUTION BEGIN TEMPLATE
  (* := insert your definition here *). Admitted.
END TEMPLATE *)

Section proofs.
Context `{!heapGS Σ, !inG Σ RA}.
Let N := nroot .@ "ticket_lock".

(**
  This time around, we know that the thread is locked by a thread with a
  specific ticket. As such, we first define a predicate [locked_by]
  which states that the lock is locked by ticket [o].
*)
Definition locked_by (γ : gname) (o : nat) : iProp Σ
(* BEGIN SOLUTION *)
  (**
    We know that the lock is locked by ticket [o] when we have ownership
    of the exclusive counter being [o].
  *)
  := own γ (◯ (Excl' o, GSet ∅)).
(* END SOLUTION BEGIN TEMPLATE
  (* := insert your definition here *). Admitted.
END TEMPLATE *)

(** The lock is locked when it has been locked by some ticket. *)
Definition locked (γ : gname) : iProp Σ :=
  ∃ o, locked_by γ o.

Lemma locked_excl γ : locked γ -∗ locked γ -∗ False.
(* SOLUTION *) Proof.
  iIntros "[%o1 H1] [%o2 H2]".
  iDestruct (own_valid_2 with "H1 H2") as %[]%auth_frag_valid_1; done.
Qed.

(**
  We will also have a predicate signifying that ticket [x] has been
  _issued_. A thread will need to have been issued ticket [x] in order
  to wait for the first counter to become [x].
*)
Definition issued (γ : gname) (x : nat) : iProp Σ
(* BEGIN SOLUTION *)
  (** A ticket is simply the singleton set over its index. *)
  := own γ (◯ (ε : option (excl nat), GSet {[x]})).
(* END SOLUTION BEGIN TEMPLATE
  (* := insert your definition here *). Admitted.
END TEMPLATE *)

Definition lock_inv (γ : gname) (lo ln : loc) (P : iProp Σ) : iProp Σ
(* BEGIN SOLUTION *)
  (**
    Our invariant will first link the authoritative fragment to the
    counters. For the second counter, this means that all tickets prior
    to the counter's current value must have been issued.

    Secondly, the lock contains either ownership of the value of the
    first counter as well as the protected resources (the queue is
    unlocked), or the current access-granting ticket (the queue is
    locked).
  *)
  := ∃ o n : nat, lo ↦ #o ∗ ln ↦ #n ∗
  own γ (● (Excl' o, GSet (set_seq 0 n))) ∗
  (
    (locked_by γ o ∗ P) ∨
    issued γ o
  ).
(* END SOLUTION BEGIN TEMPLATE
  (* := insert your definition here *). Admitted.
END TEMPLATE *)

Definition is_lock (γ : gname) (l : val) (P : iProp Σ) : iProp Σ :=
  ∃ lo ln : loc, ⌜l = (#lo, #ln)%V⌝ ∗ inv N (lock_inv γ lo ln P).

(* ================================================================= *)
(** ** Specifications *)

Lemma mk_lock_spec P :
  {{{ P }}} mk_lock #() {{{ γ l, RET l; is_lock γ l P }}}.
(* SOLUTION *) Proof.
  iIntros "%Φ HP HΦ".
  wp_lam.
  wp_alloc lo; wp_alloc ln.
  wp_pures.
  iMod (own_alloc (● (Excl' 0, GSet ∅) ⋅ ◯ (Excl' 0, GSet ∅))) as "(%γ & Hγ & Ho)".
  { by apply auth_both_valid_discrete. }
  iApply ("HΦ" $! γ).
  iExists _, _; iSplitR; first done.
  iApply inv_alloc; iExists 0, 0; eauto with iFrame.
Qed.

Lemma wait_spec γ l P x :
  {{{ is_lock γ l P ∗ issued γ x }}}
    wait #x l
  {{{ RET #(); locked γ ∗ P }}}.
(* SOLUTION *) Proof.
  iIntros "%Φ [(%lo & %ln & -> & #I) Hx] HΦ".
  iLöb as "IH".
  wp_rec.
  wp_pures.
  wp_bind (! _)%E.
  iInv "I" as "(%o & %n & Hlo & Hln & Hγ)".
  wp_load.
  destruct (decide (o = x)) as [->|].
  - iDestruct "Hγ" as "[Hγ [[Hexcl HP]|Ho]]".
    + iSplitL "Hlo Hln Hγ Hx"; first by iExists _, _; iFrame.
      iModIntro.
      wp_pures.
      rewrite bool_decide_eq_true_2 //.
      wp_pures.
      by iApply "HΦ"; iFrame.
    + iDestruct (own_valid_2 with "Hx Ho") as
        %[_ Hvl%gset_disj_valid_op]%auth_frag_valid_1;
        set_solver.
  - iSplitL "Hlo Hln Hγ"; first by iExists _, _; iFrame.
    iModIntro.
    wp_pures.
    rewrite bool_decide_eq_false_2; last naive_solver.
    wp_pures.
    iApply ("IH" with "Hx HΦ").
Qed.

Lemma acquire_spec γ l P :
  {{{ is_lock γ l P }}} acquire l {{{ RET #(); locked γ ∗ P }}}.
(* SOLUTION *) Proof.
  iIntros "%Φ (%lo & %ln & -> & #I) HΦ".
  iLöb as "IH".
  wp_rec.
  wp_pures.
  wp_bind (! _)%E.
  iInv "I" as "(%o & %n & Hlo & Hln & Hγ)".
  wp_load.
  iSplitL "Hlo Hln Hγ"; first by iExists _, _; iFrame.
  clear o.
  iModIntro.
  wp_pures.
  wp_bind (CmpXchg _ _ _).
  iInv "I" as "(%o & %n' & Hlo & Hln & Hγ)".
  destruct (decide (n' = n)) as [->|].
  - wp_cmpxchg_suc.
    rewrite Z.add_comm -(Nat2Z.inj_add 1) /=.
    iDestruct "Hγ" as "[Hγ Hγ']".
    iMod (own_update _ _ (● (Excl' o, GSet (set_seq 0 (S n))) ⋅ ◯ (ε, GSet {[n]})) with "Hγ") as "[Hγ Hn]".
    {
      apply auth_update_alloc, prod_local_update_2.
      rewrite set_seq_S_end_union_L /=.
      apply gset_disj_alloc_empty_local_update; apply (set_seq_S_end_disjoint 0).
    }
    iSplitL "Hlo Hln Hγ Hγ'"; first by iExists _, _; iFrame.
    iModIntro.
    wp_pures.
    wp_apply (wait_spec with "[I $Hn]"); first iExists _, _; eauto.
  - wp_cmpxchg_fail; first naive_solver.
    iModIntro.
    iSplitL "Hlo Hln Hγ"; first by iExists _, _; iFrame.
    wp_pures.
    by iApply "IH".
Qed.

Lemma release_spec γ l P :
  {{{ is_lock γ l P ∗ locked γ ∗ P }}} release l {{{ RET #(); True }}}.
(* SOLUTION *) Proof.
  iIntros "%Φ ((%lo & %ln & -> & #I) & [%o Hexcl] & HP) HΦ".
  wp_lam.
  wp_pures.
  wp_bind (! _)%E.
  iInv "I" as "(%o' & %n & Hlo & Hln & [Hγ [[>Hexcl' _]|Ho]])".
  { by iDestruct (own_valid_2 with "Hexcl Hexcl'") as %[]%auth_frag_valid_1. }
  wp_load.
  iDestruct (own_valid_2 with "Hγ Hexcl") as
    %[[<-%Excl_included%leibniz_equiv _]%pair_included _]%auth_both_valid_discrete.
  iModIntro.
  iSplitL "Hlo Hln Hγ Ho"; first by iFrame.
  clear n.
  wp_pures.
  rewrite Z.add_comm -(Nat2Z.inj_add 1) /=.
  iInv "I" as "(%o' & %n & Hlo & Hln & [Hγ [[>Hexcl' _]|Ho]])".
  { by iDestruct (own_valid_2 with "Hexcl Hexcl'") as %[]%auth_frag_valid. }
  wp_store.
  iDestruct (own_valid_2 with "Hγ Hexcl") as
    %[[<-%Excl_included%leibniz_equiv _]%pair_included _]%auth_both_valid_discrete.
  iCombine "Hγ Hexcl" as "Hγ".
  iMod (own_update _ _ (● (Excl' (S o), GSet (set_seq 0 n)) ⋅ ◯ (Excl' (S o), ε)) with "Hγ") as "[Hγ Hexcl]".
  { by apply auth_update, prod_local_update_1, option_local_update, exclusive_local_update. }
  iModIntro.
  iSplitR "HΦ"; last by iApply "HΦ".
  iExists _, _; eauto with iFrame.
Qed.

End proofs.
