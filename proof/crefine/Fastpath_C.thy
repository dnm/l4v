(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory Fastpath_C
imports
  SyscallArgs_C
  Delete_C
  Syscall_C
  "../../lib/clib/MonadicRewrite_C"
begin

definition
 "fastpaths sysc \<equiv> case sysc of
  SysCall \<Rightarrow> doE
    curThread \<leftarrow> liftE $ getCurThread;
    mi \<leftarrow> liftE $ getMessageInfo curThread;
    cptr \<leftarrow> liftE $ asUser curThread $ getRegister capRegister;

    fault \<leftarrow> liftE $ threadGet tcbFault curThread;
    pickFastpath \<leftarrow> liftE $ alternative (return True) (return False);
    unlessE (fault = None \<and> msgExtraCaps mi = 0
                \<and> msgLength mi \<le> scast n_msgRegisters \<and> pickFastpath)
       $ throwError ();

    ctab \<leftarrow> liftE $ getThreadCSpaceRoot curThread >>= getCTE;
    epCap \<leftarrow> unifyFailure (doE t \<leftarrow> resolveAddressBits (cteCap ctab) cptr (size cptr);
         liftE (getSlotCap (fst t)) odE);
    unlessE (isEndpointCap epCap \<and> capEPCanSend epCap)
       $ throwError ();
    ep \<leftarrow> liftE $ getEndpoint (capEPPtr epCap);
    unlessE (isRecvEP ep) $ throwError ();
    dest \<leftarrow> returnOk $ hd $ epQueue ep;
    newVTable \<leftarrow> liftE $ getThreadVSpaceRoot dest >>= getCTE;
    unlessE (isValidVTableRoot $ cteCap newVTable) $ throwError ();
    pd \<leftarrow> returnOk $ capPDBasePtr $ capCap $ cteCap newVTable;
    curPrio \<leftarrow> liftE $ threadGet tcbPriority curThread;
    destPrio \<leftarrow> liftE $ threadGet tcbPriority dest;
    destFault \<leftarrow>
    unlessE (destPrio \<ge> curPrio) $ throwError ();
    unlessE (capEPCanGrant epCap) $ throwError ();
    destST \<leftarrow> liftE $ getThreadState dest;
    unlessE (\<not> blockingIPCDiminishCaps destST) $ throwError ();
    asidMap \<leftarrow> liftE $ gets $ armKSASIDMap o ksArchState;
    unlessE (\<exists>v. {hwasid. (hwasid, pd) \<in> ran asidMap} = {v})
        $ throwError ();
    curDom \<leftarrow> liftE $ curDomain;
    destDom \<leftarrow> liftE $ threadGet tcbDomain dest;
    unlessE (destDom = curDom) $ throwError ();

    liftE $ do
      setEndpoint (capEPPtr epCap)
           (case tl (epQueue ep) of [] \<Rightarrow> IdleEP | _ \<Rightarrow> RecvEP (tl (epQueue ep)));
      threadSet (tcbState_update (\<lambda>_. BlockedOnReply)) curThread;
      replySlot \<leftarrow> getThreadReplySlot curThread;
      callerSlot \<leftarrow> getThreadCallerSlot dest;
      replySlotCTE \<leftarrow> getCTE replySlot;
      assert (mdbNext (cteMDBNode replySlotCTE) = 0
                   \<and> isReplyCap (cteCap replySlotCTE)
                   \<and> capReplyMaster (cteCap replySlotCTE)
                   \<and> mdbFirstBadged (cteMDBNode replySlotCTE)
                   \<and> mdbRevocable (cteMDBNode replySlotCTE));
      cteInsert (ReplyCap curThread False) replySlot callerSlot;

      forM_x (take (unat (msgLength mi)) State_H.msgRegisters)
             (\<lambda>r. do v \<leftarrow> asUser curThread (getRegister r);
                    asUser dest (setRegister r v) od);
      setThreadState Running dest;
      ArchThreadDecls_H.switchToThread dest;
      setCurThread dest;

      asUser dest $ zipWithM_x setRegister
               [State_H.badgeRegister, State_H.msgInfoRegister]
               [capEPBadge epCap, wordFromMessageInfo (mi\<lparr> msgCapsUnwrapped := 0 \<rparr>)]
    od

  odE <catch> (\<lambda>_. callKernel (SyscallEvent sysc))
  | SysReplyWait \<Rightarrow> doE
    curThread \<leftarrow> liftE $ getCurThread;
    mi \<leftarrow> liftE $ getMessageInfo curThread;
    cptr \<leftarrow> liftE $ asUser curThread $ getRegister capRegister;

    fault \<leftarrow> liftE $ threadGet tcbFault curThread;
    pickFastpath \<leftarrow> liftE $ alternative (return True) (return False);
    unlessE (fault = None \<and> msgExtraCaps mi = 0
                \<and> msgLength mi \<le> scast n_msgRegisters \<and> pickFastpath)
       $ throwError ();

    ctab \<leftarrow> liftE $ getThreadCSpaceRoot curThread >>= getCTE;
    epCap \<leftarrow> unifyFailure (doE t \<leftarrow> resolveAddressBits (cteCap ctab) cptr (size cptr);
         liftE (getSlotCap (fst t)) odE);
    unlessE (isEndpointCap epCap \<and> capEPCanReceive epCap)
       $ throwError ();
    ep \<leftarrow> liftE $ getEndpoint (capEPPtr epCap);
    unlessE (\<not> isSendEP ep) $ throwError ();

    callerSlot \<leftarrow> liftE $ getThreadCallerSlot curThread;
    callerCTE \<leftarrow> liftE $ getCTE callerSlot;
    callerCap \<leftarrow> returnOk $ cteCap callerCTE;
    unlessE (isReplyCap callerCap \<and> \<not> capReplyMaster callerCap)
       $ throwError ();

    caller \<leftarrow> returnOk $ capTCBPtr callerCap;
    callerFault \<leftarrow> liftE $ threadGet tcbFault caller;
    unlessE (callerFault = None) $ throwError ();
    newVTable \<leftarrow> liftE $ getThreadVSpaceRoot caller >>= getCTE;
    unlessE (isValidVTableRoot $ cteCap newVTable) $ throwError ();
    pd \<leftarrow> returnOk $ capPDBasePtr $ capCap $ cteCap newVTable;
    curPrio \<leftarrow> liftE $ threadGet tcbPriority curThread;
    callerPrio \<leftarrow> liftE $ threadGet tcbPriority caller;
    unlessE (callerPrio \<ge> curPrio) $ throwError ();
    asidMap \<leftarrow> liftE $ gets $ armKSASIDMap o ksArchState;
    unlessE (\<exists>v. {hwasid. (hwasid, pd) \<in> ran asidMap} = {v})
        $ throwError ();
    curDom \<leftarrow> liftE $ curDomain;
    callerDom \<leftarrow> liftE $ threadGet tcbDomain caller;
    unlessE (callerDom = curDom) $ throwError ();

    liftE $ do
      threadSet (tcbState_update (\<lambda>_. BlockedOnReceive (capEPPtr epCap)
                                        (\<not> capEPCanSend epCap))) curThread;
      setEndpoint (capEPPtr epCap)
           (case ep of IdleEP \<Rightarrow> RecvEP [curThread] | RecvEP ts \<Rightarrow> RecvEP (ts @ [curThread]));
      mdbPrev \<leftarrow> liftM (mdbPrev o cteMDBNode) $ getCTE callerSlot;
      assert (mdbPrev \<noteq> 0);
      updateMDB mdbPrev (mdbNext_update (K 0) o mdbFirstBadged_update (K True)
                                              o mdbRevocable_update (K True));
      setCTE callerSlot makeObject;

      forM_x (take (unat (msgLength mi)) State_H.msgRegisters)
             (\<lambda>r. do v \<leftarrow> asUser curThread (getRegister r);
                    asUser caller (setRegister r v) od);
      setThreadState Running caller;
      ArchThreadDecls_H.switchToThread caller;
      setCurThread caller;

      asUser caller $ zipWithM_x setRegister
               [State_H.badgeRegister, State_H.msgInfoRegister]
               [0, wordFromMessageInfo (mi\<lparr> msgCapsUnwrapped := 0 \<rparr>)]
    od

  odE <catch> (\<lambda>_. callKernel (SyscallEvent sysc))

  | _ \<Rightarrow> callKernel (SyscallEvent sysc)"


lemma setCTE_obj_at'_queued:
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbQueued tcb)) t\<rbrace> setCTE p v \<lbrace>\<lambda>rv. obj_at' (\<lambda>tcb. P (tcbQueued tcb)) t\<rbrace>"
  unfolding setCTE_def
  by (rule setObject_cte_obj_at_tcb', simp+)

crunch obj_at'_queued: cteInsert "obj_at' (\<lambda>tcb. P (tcbQueued tcb)) t"
  (wp: setCTE_obj_at'_queued crunch_wps)

crunch obj_at'_not_queued: emptySlot "obj_at' (\<lambda>a. \<not> tcbQueued a) p"
  (wp: setCTE_obj_at'_queued)

lemma getEndpoint_obj_at':
  "\<lbrace>obj_at' P ptr\<rbrace> getEndpoint ptr \<lbrace>\<lambda>rv s. P rv\<rbrace>"
  apply (wp getEndpoint_wp)
  apply (clarsimp simp: obj_at'_def projectKOs)
  done

lemma setEndpoint_obj_at_tcb':
  "\<lbrace>obj_at' (P :: tcb \<Rightarrow> bool) p\<rbrace> setEndpoint p' val \<lbrace>\<lambda>rv. obj_at' P p\<rbrace>"
  apply (simp add: setEndpoint_def)
  apply (rule obj_at_setObject2)
  apply (clarsimp simp: updateObject_default_def in_monad)
  done

lemma tcbSchedEnqueue_obj_at_unchangedT:
  assumes y: "\<And>f. \<forall>tcb. P (tcbQueued_update f tcb) = P tcb"
  shows  "\<lbrace>obj_at' P t\<rbrace> tcbSchedEnqueue t' \<lbrace>\<lambda>rv. obj_at' P t\<rbrace>"
  apply (simp add: tcbSchedEnqueue_def unless_def)
  apply (wp | simp add: y)+
  done

(* FIXME: Move to Schedule_R.thy. Make Arch_switchToThread_obj_at a specialisation of this *)
lemma Arch_switchToThread_obj_at_pre:
  "\<lbrace>obj_at' P t\<rbrace>
   ArchThreadDecls_H.switchToThread t
   \<lbrace>\<lambda>rv. obj_at' P t\<rbrace>"
  apply (simp add: ArchThread_H.switchToThread_def storeWordUser_def)
  apply (wp doMachineOp_obj_at setVMRoot_obj_at hoare_drop_imps)
  done

lemma rescheduleRequired_obj_at_unchangedT:
  assumes y: "\<And>f. \<forall>tcb. P (tcbQueued_update f tcb) = P tcb"
  shows  "\<lbrace>obj_at' P t\<rbrace> rescheduleRequired \<lbrace>\<lambda>rv. obj_at' P t\<rbrace>"
  apply (simp add: rescheduleRequired_def)
  apply (wp tcbSchedEnqueue_obj_at_unchangedT[OF y] | wpc)+
  apply simp
  done

lemma setThreadState_obj_at_unchangedT:
  assumes x: "\<And>f. \<forall>tcb. P (tcbState_update f tcb) = P tcb"
  assumes y: "\<And>f. \<forall>tcb. P (tcbQueued_update f tcb) = P tcb"
  shows "\<lbrace>obj_at' P t\<rbrace> setThreadState t' ts \<lbrace>\<lambda>rv. obj_at' P t\<rbrace>"
  apply (simp add: setThreadState_def)
  apply (wp rescheduleRequired_obj_at_unchangedT[OF y], simp)
  apply (wp threadSet_obj_at')
  apply (clarsimp simp: obj_at'_def projectKOs x cong: if_cong)
  done

lemmas setThreadState_obj_at_unchanged
    = setThreadState_obj_at_unchangedT[OF all_tcbI all_tcbI]

lemma tcbSchedEnqueue_tcbContext[wp]:
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbContext tcb)) t\<rbrace>
     tcbSchedEnqueue t'
   \<lbrace>\<lambda>rv. obj_at' (\<lambda>tcb. P (tcbContext tcb)) t\<rbrace>"
  apply (rule tcbSchedEnqueue_obj_at_unchangedT[OF all_tcbI])
  apply simp
  done

lemma setAsyncEP_tcb:
  "\<lbrace>obj_at' (\<lambda>tcb::tcb. P tcb) t\<rbrace>
  setAsyncEP aep e
  \<lbrace>\<lambda>_. obj_at' P t\<rbrace>"
  apply (simp add: setAsyncEP_def)
  apply (rule obj_at_setObject2)
  apply (clarsimp simp: updateObject_default_def in_monad)
  done

lemma setCTE_tcbContext:
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbContext tcb)) t\<rbrace>
  setCTE slot cte
  \<lbrace>\<lambda>rv. obj_at' (\<lambda>tcb. P (tcbContext tcb)) t\<rbrace>"
  apply (simp add: setCTE_def)
  apply (rule setObject_cte_obj_at_tcb', simp_all)
  done

crunch tcbContext[wp]: deleteCallerCap "obj_at' (\<lambda>tcb. P (tcbContext tcb)) t"
  (wp: setEndpoint_obj_at_tcb' setThreadState_obj_at_unchanged
       setAsyncEP_tcb crunch_wps
      simp: crunch_simps unless_def)

crunch ksArch[wp]: asUser "\<lambda>s. P (ksArchState s)"
  (wp: crunch_wps)


definition
   tcbs_of :: "kernel_state => word32 => tcb option"
where
  "tcbs_of s = (%x. if tcb_at' x s then projectKO_opt (the (ksPSpace s x)) else None)"

lemma obj_at_tcbs_of:
  "obj_at' P t s = (EX tcb. tcbs_of s t = Some tcb & P tcb)"
  apply (simp add: tcbs_of_def split: split_if)
  apply (intro conjI impI)
   apply (clarsimp simp: obj_at'_def projectKOs)
  apply (clarsimp simp: obj_at'_weakenE[OF _ TrueI])
  done

lemma st_tcb_at_tcbs_of:
  "st_tcb_at' P t s = (EX tcb. tcbs_of s t = Some tcb & P (tcbState tcb))"
  by (simp add: st_tcb_at'_def obj_at_tcbs_of)

context kernel_m begin

lemma ccorres_disj_division:
  "\<lbrakk> P \<or> Q; P \<Longrightarrow> ccorres_underlying sr G r xf ar axf R S hs a c;
      Q \<Longrightarrow> ccorres_underlying sr G r xf ar axf T U hs a c \<rbrakk>
     \<Longrightarrow> ccorres_underlying sr G r xf ar axf
             (\<lambda>s. (P \<longrightarrow> R s) \<and> (Q \<longrightarrow> T s)) {s. (P \<longrightarrow> s \<in> S) \<and> (Q \<longrightarrow> s \<in> U)}
                hs a c"
  apply (erule disjE, simp_all)
   apply (auto elim!: ccorres_guard_imp)
  done

lemma disj_division_bool: "b \<or> \<not> b" by simp

lemmas ccorres_case_bools2 = ccorres_disj_division [OF disj_division_bool]

lemma capMasterCap_NullCap_eq:
  "(capMasterCap c = NullCap) = (c = NullCap)"
  by (auto dest!: capMasterCap_eqDs)

lemma getCTE_h_val_ccorres_split:
  assumes var: "\<And>s f s'. var (var_update f s) = f (var s)
                  \<and> ((s', var_update f s) \<in> rf_sr) = ((s', s) \<in> rf_sr)"
     and "\<And>rv' t t'. ceqv \<Gamma> var rv' t t' g (g' rv')"
     and "\<And>rv rv'. \<lbrakk> ccap_relation (cteCap rv) rv'; P rv \<rbrakk>
                \<Longrightarrow> ccorres r xf (Q rv) (Q' rv rv') hs (f rv) (g' rv')"
  shows
  "ccorres r xf (\<lambda>s. \<forall>cte. ctes_of s slot = Some cte \<longrightarrow> P cte \<and> Q cte s)
                {s. (\<forall>cte cap. ccap_relation (cteCap cte) cap \<and> P cte
                          \<longrightarrow> var_update (\<lambda>_. cap) s \<in> Q' cte cap)
                           \<and> slot' = cte_Ptr slot} hs
       (getCTE slot >>= (\<lambda>rv. f rv))
   ((Basic (\<lambda>s. var_update (\<lambda>_. h_val (hrs_mem (t_hrs_' (globals s))) (cap_Ptr &(slot' \<rightarrow>[''cap_C'']))) s));; g)"
    (is "ccorres r xf ?G ?G' hs ?f ?g")
  apply (rule ccorres_guard_imp2)
   apply (rule ccorres_pre_getCTE)
   apply (rule_tac A="cte_wp_at' (op = rv and P) slot and Q rv" and A'="?G'" in ccorres_guard_imp2)
    apply (rule_tac P="P rv" in ccorres_gen_asm)
    apply (rule ccorres_symb_exec_r)
      apply (rule_tac xf'=var in ccorres_abstract)
       apply (rule assms)
      apply (rule ccorres_gen_asm2, erule(1) assms)
     apply vcg
    apply (rule conseqPre, vcg, clarsimp simp: var)
   apply (clarsimp simp: cte_wp_at_ctes_of var)
   apply (erule(1) cmap_relationE1[OF cmap_relation_cte])
   apply (clarsimp simp: typ_heap_simps' dest!: ccte_relation_ccap_relation)
  apply (clarsimp simp: cte_wp_at_ctes_of)
  done

lemma cap_'_cap_'_update_var_props:
  "cap_' (cap_'_update f s) = f (cap_' s) \<and>
         ((s', cap_'_update f s) \<in> rf_sr) = ((s', s) \<in> rf_sr)"
  by simp

lemmas getCTE_cap_h_val_ccorres_split
    = getCTE_h_val_ccorres_split[where var_update=cap_'_update and P=\<top>,
                                 OF cap_'_cap_'_update_var_props]

lemma getCTE_ccorres_helper:
  "\<lbrakk> \<And>\<sigma> cte cte'. \<Gamma> \<turnstile> {s. (\<sigma>, s) \<in> rf_sr \<and> P \<sigma> \<and> s \<in> P' \<and> ctes_of \<sigma> slot = Some cte
                               \<and> cslift s (cte_Ptr slot) = Some cte'
                               \<and> ccte_relation cte cte'}
                       f {s. (\<sigma>, s) \<in> rf_sr \<and> r cte (xf s)} \<rbrakk> \<Longrightarrow>
     ccorres r xf P P' hs (getCTE slot) f"
  apply atomize
  apply (rule ccorres_guard_imp2)
   apply (rule ccorres_add_return2)
   apply (rule ccorres_pre_getCTE)
   apply (rule_tac P="cte_wp_at' (op = x) slot and P"
                in ccorres_from_vcg[where P'=P'])
   apply (erule allEI)
   apply (drule_tac x="the (ctes_of \<sigma> slot)" in spec)
   apply (erule HoarePartial.conseq)
   apply (clarsimp simp: return_def cte_wp_at_ctes_of)
   apply (erule(1) cmap_relationE1[OF cmap_relation_cte])
   apply simp
  apply (clarsimp simp: cte_wp_at_ctes_of)
  done

lemma acc_CNodeCap_repr:
  "isCNodeCap cap
     \<Longrightarrow> cap = CNodeCap (capCNodePtr cap) (capCNodeBits cap)
                        (capCNodeGuard cap) (capCNodeGuardSize cap)"
  by (clarsimp simp: isCap_simps)

lemma valid_cnode_cap_cte_at':
  "\<lbrakk> s \<turnstile>' c; isCNodeCap c; ptr = capCNodePtr c; v < 2 ^ capCNodeBits c \<rbrakk>
      \<Longrightarrow> cte_at' (ptr + v * 0x10) s"
  apply (drule less_mask_eq)
  apply (drule(1) valid_cap_cte_at'[where addr=v])
  apply (simp add: mult.commute mult.left_commute)
  done

lemma ccorres_abstract_all:
  "\<lbrakk>\<And>rv' t t'. ceqv Gamm xf' rv' t t' d (d' rv');
    \<And>rv'. ccorres_underlying sr Gamm r xf arrel axf (G rv') (G' rv') hs a (d' rv')\<rbrakk>
       \<Longrightarrow> ccorres_underlying sr Gamm r xf arrel axf (\<lambda>s. \<forall>rv'. G rv' s) {s. s \<in> G' (xf' s)} hs a d"
  apply (erule ccorres_abstract)
  apply (rule ccorres_guard_imp2)
   apply assumption
  apply simp
  done

lemma of_int_sint_scast [simp]:
  "of_int (sint (x :: 'a::len word)) = (scast x :: 'b::len word)"
  by (metis scast_def word_of_int)

lemma cap_capType_equals_spec:
  "\<forall>s. \<Gamma>\<turnstile> {s} Call cap_capType_equals_'proc \<lbrace>\<acute>ret__int = of_bl [cap_get_tag \<^bsup>s\<^esup>cap = \<^bsup>s\<^esup>cap_type_tag]\<rbrace>"
  apply (rule allI, rule conseqPre)
   apply (hoare_rule HoarePartial.ProcNoRec1)
   apply vcg
  apply (clarsimp simp: cap_get_tag_eq_x mask_def split: split_if)
  apply (simp add: word_sless_def word_sle_def)
  done

lemma of_bl_from_bool:
  "of_bl [x] = from_bool x"
  by (cases x, simp_all)

lemma lookup_fp_ccorres':
  assumes bits: "bits = size cptr"
  shows
  "ccorres (\<lambda>mcp ccp. ccap_relation (case mcp of Inl v => NullCap | Inr v => v) ccp)
                ret__struct_cap_C_'
           (valid_cap' cap and valid_objs')
           (UNIV \<inter> {s. ccap_relation cap (cap_' s)} \<inter> {s. cptr_' s = cptr}) []
       (cutMon (op = s) (doE t \<leftarrow> resolveAddressBits cap cptr bits;
                             liftE (getSlotCap (fst t))
                         odE))
       (Call lookup_fp_'proc)"
  apply (cinit' lift: cptr_')
   apply (rule ccorres_rhs_assoc2)
   apply (rule ccorres_symb_exec_r)
     apply (rule_tac xf'=ret__int_' in ccorres_abstract, ceqv)
     apply (rule_tac P="rv' = from_bool (isCNodeCap cap)" in ccorres_gen_asm2)
     apply (simp add: from_bool_0 del: Collect_const cong: call_ignore_cong)
     apply (rule ccorres_Cond_rhs_Seq)
      apply (simp add: resolveAddressBits.simps split_def del: Collect_const
                      split del: split_if)
      apply (rule ccorres_drop_cutMon)
      apply (rule ccorres_from_vcg_split_throws[where P=\<top> and P'=UNIV])
       apply vcg
      apply (rule conseqPre, vcg)
      apply (clarsimp simp: throwError_def return_def isRight_def isLeft_def
                            ccap_relation_NullCap_iff)
     apply (clarsimp simp del: Collect_const cong: call_ignore_cong)
     apply (rule_tac P="valid_cap' cap and valid_objs'"
                and P'="UNIV \<inter> {s. ccap_relation cap (cap_' s) \<and> isCNodeCap cap}
                             \<inter> {s. bits___unsigned_long_' s = 32 - of_nat bits \<and> bits \<le> 32 \<and> bits \<noteq> 0}"
                   in ccorres_inst)
     apply (thin_tac "isCNodeCap cap")
     defer
     apply vcg
    apply (rule conseqPre, vcg)
    apply clarsimp
   apply (clarsimp simp: word_size cap_get_tag_isCap bits
                         of_bl_from_bool from_bool_0)
  proof (induct cap cptr bits arbitrary: s
            rule: resolveAddressBits.induct)
  case (1 acap acptr abits as)

    have sub_mask_neq_0_eq:
      "\<And>v :: word32. v && 0x1F \<noteq> 0 \<Longrightarrow> 0x20 - (0x20 - (v && 0x1F) && mask 5) = v && 0x1F"
      apply (subst word_le_mask_eq)
        apply (simp only: mask_def)
        apply (rule word_le_minus_mono, simp_all add: word_le_sub1 word_sub_le_iff)[1]
        apply (rule order_trans, rule word_and_le1, simp)
       apply (simp add: word_bits_def)
      apply simp
      done

    have valid_cnode_bits_0:
      "\<And>s acap. \<lbrakk> isCNodeCap acap; s \<turnstile>' acap \<rbrakk> \<Longrightarrow> capCNodeBits acap \<noteq> 0"
      by (clarsimp simp: isCap_simps valid_cap'_def)

    have cap_get_tag_update_1:
      "\<And>f cap. cap_get_tag (cap_C.words_C_update (\<lambda>w. Arrays.update w (Suc 0) (f w)) cap) = cap_get_tag cap"
      by (simp add: cap_get_tag_def)

    show ?case
    apply (cinitlift cap_' bits___unsigned_long_')
    apply (rename_tac cbits ccap)
    apply (elim conjE)
    apply (rule_tac F="capCNodePtr_CL (cap_cnode_cap_lift ccap)
                             = capCNodePtr acap
                        \<and> capCNodeGuardSize acap < 32
                        \<and> capCNodeBits acap < 32
                        \<and> capCNodeGuard_CL (cap_cnode_cap_lift ccap)
                             = capCNodeGuard acap
                        \<and> unat (capCNodeGuardSize_CL (cap_cnode_cap_lift ccap))
                             = capCNodeGuardSize acap
                        \<and> unat (capCNodeRadix_CL (cap_cnode_cap_lift ccap))
                             = capCNodeBits acap
                        \<and> unat (0x20 - capCNodeRadix_CL (cap_cnode_cap_lift ccap))
                             = 32 - capCNodeBits acap
                        \<and> unat ((0x20 :: word32) - of_nat abits) = 32 - abits
                        \<and> unat (capCNodeGuardSize_CL (cap_cnode_cap_lift ccap)
                                 + capCNodeRadix_CL (cap_cnode_cap_lift ccap))
                             = capCNodeGuardSize acap + capCNodeBits acap"
                   in Corres_UL_C.ccorres_req)
     apply (clarsimp simp: cap_get_tag_isCap[symmetric])
     apply (clarsimp simp: cap_lift_cnode_cap cap_to_H_simps valid_cap'_def
                           capAligned_def cap_cnode_cap_lift_def objBits_simps
                           word_mod_2p_is_mask[where n=5, simplified]
                    elim!: ccap_relationE)
     apply (simp add: unat_sub[unfolded word_le_nat_alt]
                      unat_of_nat32 word_bits_def)
     apply (subst unat_plus_simple[symmetric], subst no_olen_add_nat)
     apply (rule order_le_less_trans, rule add_le_mono)
       apply (rule word_le_nat_alt[THEN iffD1], rule word_and_le1)+
     apply simp
    apply (rule ccorres_guard_imp2)
     apply csymbr+
     apply (rule ccorres_Guard_Seq, csymbr)
     apply (simp add: resolveAddressBits.simps bindE_assoc
                 split del: split_if del: Collect_const cong: call_ignore_cong)
     apply (simp add: cutMon_walk_bindE del: Collect_const
                         split del: split_if cong: call_ignore_cong)
     apply (rule ccorres_drop_cutMon_bindE, rule ccorres_assertE)
     apply (rule ccorres_cutMon)
     apply (rule_tac P="abits < capCNodeBits acap + capCNodeGuardSize acap"
                 in ccorres_case_bools2)
      apply (rule ccorres_drop_cutMon)
      apply (simp del: Collect_const cong: call_ignore_cong)
      apply csymbr+
      apply (rule ccorres_symb_exec_r)
        apply (rule_tac xf'=ret__int_' in ccorres_abstract_all, ceqv)
        apply (rule ccorres_Cond_rhs_Seq)
         apply (rule ccorres_from_vcg_split_throws[where P=\<top> and P'=UNIV])
          apply vcg
         apply (rule conseqPre, vcg)
         apply (clarsimp simp: unlessE_def split: split_if)
         apply (simp add: throwError_def return_def cap_tag_defs
                          isRight_def isLeft_def
                          ccap_relation_NullCap_iff)
         apply fastforce
        apply (simp del: Collect_const cong: call_ignore_cong)
        apply (rule ccorres_Guard_Seq)+
        apply csymbr+
        apply (simp del: Collect_const cong: call_ignore_cong)
        apply (rule ccorres_move_c_guard_cte)
        apply (rule ccorres_symb_exec_r)
          apply csymbr+
          apply (rule ccorres_cond_false_seq)
          apply (simp add: ccorres_expand_while_iff_Seq[symmetric]
                           whileAnno_def cong: call_ignore_cong)
          apply (rule ccorres_cond_false)
          apply (rule ccorres_cond_true_seq)
          apply (rule ccorres_from_vcg_split_throws[where P=\<top> and P'=UNIV])
           apply vcg
          apply (rule conseqPre, vcg)
          apply (clarsimp simp: unlessE_def split: split_if cong: call_ignore_cong)
          apply (simp add: throwError_def return_def cap_tag_defs isRight_def
                           isLeft_def ccap_relation_NullCap_iff)
          apply fastforce
         apply (simp del: Collect_const)
         apply vcg
        apply (rule conseqPre, vcg, clarsimp)
       apply (simp del: Collect_const)
       apply vcg
      apply (rule conseqPre, vcg, clarsimp)
     apply (simp add: cutMon_walk_bindE unlessE_whenE
                 del: Collect_const
                 split del: split_if cong: call_ignore_cong)
     apply (rule ccorres_drop_cutMon_bindE)
     apply csymbr+
     apply (rule ccorres_rhs_assoc2)
     apply (rule_tac r'=dc and xf'=xfdc in ccorres_splitE[OF _ ceqv_refl])
        apply (rule ccorres_Cond_rhs_Seq)
         apply (rule ccorres_Guard_Seq)
         apply csymbr
         apply (simp add: unat_sub word_le_nat_alt if_1_0_0 shiftl_shiftr3 word_size
                     del: Collect_const)
         apply (rule ccorres_Cond_rhs)
          apply (rule ccorres_from_vcg_throws[where P=\<top> and P'=UNIV])
          apply (rule allI, rule conseqPre, vcg)
          apply (clarsimp simp: whenE_def throwError_def return_def
                                ccap_relation_NullCap_iff isRight_def isLeft_def)
         apply (simp add: whenE_def)
         apply (rule ccorres_returnOk_skip)
        apply simp
        apply (rule ccorres_cond_false)
        apply (rule_tac P="valid_cap' acap" in ccorres_from_vcg[where P'=UNIV])
        apply (rule allI, rule conseqPre, vcg)
        apply (clarsimp simp: valid_cap'_def isCap_simps if_1_0_0)
        apply (simp add: unat_eq_0[symmetric] whenE_def returnOk_def return_def)
      apply (rule ccorres_cutMon)
       apply (simp add: liftE_bindE locateSlot_conv
                   del: Collect_const cong: call_ignore_cong)
       apply (rule_tac P="abits = capCNodeBits acap + capCNodeGuardSize acap"
                   in ccorres_case_bools2)
        apply (rule ccorres_drop_cutMon)
        apply (simp del: Collect_const)
        apply (simp add: liftE_def getSlotCap_def del: Collect_const)
        apply (rule ccorres_Guard_Seq)+
        apply csymbr+
        apply (simp add:ccorres_rhs_assoc)
        apply (rule ccorres_move_c_guard_cte)
        apply (rule getCTE_cap_h_val_ccorres_split)
         apply ceqv
        apply (rename_tac "getCTE_cap")
        apply csymbr+
        apply (rule ccorres_cond_false_seq)
        apply (simp add: ccorres_expand_while_iff_Seq[symmetric]
                         whileAnno_def del: Collect_const)
        apply (rule ccorres_cond_false)
        apply (rule ccorres_cond_false_seq)
        apply (simp del: Collect_const)
        apply (rule_tac P'="{s. cap_' s = getCTE_cap}"
                       in ccorres_from_vcg_throws[where P=\<top>])
        apply (rule allI, rule conseqPre, vcg)
        apply (clarsimp simp: word_sle_def return_def returnOk_def
                              isRight_def)
       apply (simp add: bind_bindE_assoc
                   del: Collect_const cong: call_ignore_cong if_cong)
       apply (simp add: liftE_bindE "1.prems" unlessE_def
                        cutMon_walk_bind cnode_cap_case_if
                   del: Collect_const cong: if_cong call_ignore_cong)
       apply (rule ccorres_Guard_Seq)+
       apply csymbr+
       apply (simp del: Collect_const cong: call_ignore_cong)
       apply (rule ccorres_drop_cutMon_bind)
       apply (rule ccorres_getSlotCap_cte_at)
       apply (rule ccorres_move_c_guard_cte)
       apply ctac
         apply csymbr+
         apply (rule ccorres_cond_true_seq)
         apply (rule ccorres_rhs_assoc | csymbr)+
         apply (simp add: ccorres_expand_while_iff_Seq[symmetric]
                          whileAnno_def if_to_top_of_bindE bindE_assoc
                          split_def
                    cong: if_cong call_ignore_cong)
         apply (rule ccorres_cutMon)
         apply (simp add: cutMon_walk_if cong: call_ignore_cong)
         apply (rule_tac Q'="\<lambda>s. ret__int_' s = from_bool (isCNodeCap rv)"
                       in ccorres_cond_both'[where Q=\<top>])
           apply (clarsimp simp: from_bool_0)
          apply (rule ccorres_rhs_assoc)+
          apply (rule_tac P="ccorres r xf Gd Gd' hs a" for r xf Gd Gd' hs a in rsubst)
           apply (rule "1.hyps",
                  (rule refl in_returns in_bind[THEN iffD2, OF exI, OF exI, OF conjI]
                       acc_CNodeCap_repr
                        | assumption
                        | clarsimp simp: unlessE_whenE locateSlot_conv
                                         "1.prems"
                        | clarsimp simp: whenE_def[where P=False])+)[1]
          apply (simp add: whileAnno_def)
         apply (rule ccorres_drop_cutMon)
         apply (simp add: liftE_def getSlotCap_def)
         apply (rule ccorres_pre_getCTE)
         apply (rule ccorres_cond_false_seq)
         apply (rule_tac P="\<lambda>s. cteCap rva = rv" and P'="{s. cap_' s = cap}"
                      in ccorres_from_vcg_throws)
         apply (rule allI, rule conseqPre, vcg)
         apply (clarsimp simp: return_def returnOk_def word_sle_def isRight_def)
        apply simp
        apply (wp getSlotCap_wp)
       apply (simp add: if_1_0_0)
       apply vcg
      apply (wp whenE_throwError_wp)
     apply (simp add: ccHoarePost_def del: Collect_const)
     apply vcg
    apply (clarsimp simp: Collect_const_mem if_1_0_0 of_bl_from_bool
               split del: split_if cong: if_cong)
    apply (clarsimp simp: cap_get_tag_isCap)
    apply (clarsimp simp: word_less_nat_alt word_le_nat_alt linorder_not_less
                    cong: conj_cong)
    apply (clarsimp simp: word_less_nat_alt word_le_nat_alt linorder_not_less
                    cong: rev_conj_cong)
    apply (frule(1) valid_cnode_bits_0, clarsimp)
    apply (intro conjI impI)
                     apply (simp add: size_of_def)
                     apply (erule (1) valid_cnode_cap_cte_at')
                      apply simp
                     apply (rule shiftr_less_t2n')
                      apply simp
                     apply simp
                    apply (simp add:size_of_def)
                    apply (erule (1) valid_cnode_cap_cte_at')
                     apply simp
                    apply (rule shiftr_less_t2n')
                     apply simp
                    apply simp
                   apply (clarsimp simp: cte_wp_at_ctes_of)
                   apply (clarsimp dest!: ctes_of_valid')
                  apply (simp add: cte_level_bits_def size_of_def field_simps)
                  apply (simp add: shiftl_shiftr3 word_size)
                  apply (simp add: word_bw_assocs mask_and_mask min.absorb2)
                 apply (simp_all add: unat_sub word_le_nat_alt unat_eq_0[symmetric])
               apply (simp_all add: unat_plus_if' if_P)
           apply (clarsimp simp: rightsFromWord_and shiftr_over_and_dist
                                 size_of_def cte_level_bits_def field_simps shiftl_shiftl
                                 shiftl_shiftr3 word_size)+
         apply (clarsimp simp: unat_gt_0 from_bool_0 trans [OF eq_commute from_bool_eq_if])
         apply (intro conjI impI, simp_all)[1]
         apply (rule word_unat.Rep_inject[THEN iffD1], subst unat_plus_if')
         apply (simp add: unat_plus_if' unat_of_nat32 word_bits_def)
        apply (clarsimp simp: rightsFromWord_and shiftr_over_and_dist
                              size_of_def cte_level_bits_def field_simps shiftl_shiftl
                              shiftl_shiftr3 word_size)+
      apply (clarsimp simp: unat_gt_0 from_bool_0 trans [OF eq_commute from_bool_eq_if])

      apply (intro conjI impI, simp_all)[1]
      apply (rule word_unat.Rep_inject[THEN iffD1], simp add: unat_of_nat32 word_bits_def)
    done
qed

lemmas lookup_fp_ccorres
    = lookup_fp_ccorres'[OF refl, THEN ccorres_use_cutMon]

lemma ccap_relation_case_sum_Null_endpoint:
  "ccap_relation (case x of Inl v => NullCap | Inr v => v) ccap
     \<Longrightarrow> (cap_get_tag ccap = scast cap_endpoint_cap)
           = (isRight x \<and> isEndpointCap (theRight x))"
  by (clarsimp simp: cap_get_tag_isCap isRight_def isCap_simps
              split: sum.split_asm)

lemma empty_fail_isRunnable:
  "empty_fail (isRunnable t)"
  by (simp add: isRunnable_def isBlocked_def)

lemma findPDForASID_pd_at_asid_noex:
  "\<lbrace>pd_at_asid' pd asid\<rbrace> findPDForASID asid \<lbrace>\<lambda>rv s. rv = pd\<rbrace>,\<lbrace>\<bottom>\<bottom>\<rbrace>"
  apply (simp add: findPDForASID_def
             liftME_def bindE_assoc
             cong: option.case_cong)
  apply (rule seqE, rule assertE_sp)+
  apply (rule seqE, rule liftE_wp, rule gets_sp)
  apply (rule hoare_pre)
   apply (rule seqE[rotated])
    apply wpc
     apply wp[1]
    apply (rule seqE[rotated])
     apply (rule seqE[rotated])
      apply (rule returnOk_wp)
     apply (simp add:checkPDAt_def)
     apply wp[1]
    apply (rule assertE_wp)
   apply wpc
    apply wp[1]
   apply (rule liftE_wp)
   apply (rule getASID_wp)
  apply (clarsimp simp: pd_at_asid'_def obj_at'_def projectKOs
                        inv_ASIDPool)
  done

lemma ccorres_catch_bindE_symb_exec_l:
  "\<lbrakk> \<And>s. \<lbrace>op = s\<rbrace> f \<lbrace>\<lambda>rv. op = s\<rbrace>; empty_fail f;
      \<And>rv. ccorres_underlying sr G r xf ar axf (Q rv) (Q' rv) hs (catch (g rv) h >>= j) c;
      \<And>ex. ccorres_underlying sr G r xf ar axf (R ex) (R' ex) hs (h ex >>= j) c;
      \<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>,\<lbrace>R\<rbrace> \<rbrakk>
    \<Longrightarrow>
  ccorres_underlying sr G r xf ar axf P {s. (\<forall>rv. s \<in> Q' rv) \<and> (\<forall>ex. s \<in> R' ex)} hs
          (catch (f >>=E g) h >>= j) c"
  apply (simp add: catch_def bindE_def bind_assoc lift_def)
  apply (rule ccorres_guard_imp2)
   apply (rule ccorres_symb_exec_l[where G=P])
      apply wpc
       apply (simp add: throwError_bind)
       apply assumption+
    apply (clarsimp simp: valid_def validE_def split_def split: sum.split_asm)
   apply assumption
  apply clarsimp
  done

lemmas ccorres_catch_symb_exec_l
    = ccorres_catch_bindE_symb_exec_l[where g=returnOk,
                                      simplified bindE_returnOk returnOk_catch_bind]


lemma ccorres_alt_rdonly_bind:
  "\<lbrakk> ccorres_underlying sr Gamm r xf arrel axf A A' hs
              (f >>= (\<lambda>x. alternative (g x) h)) c;
       \<And>s. \<lbrace>op = s\<rbrace> f \<lbrace>\<lambda>rv. op = s\<rbrace>; empty_fail f \<rbrakk>
   \<Longrightarrow> ccorres_underlying sr Gamm r xf arrel axf A A' hs
              (alternative (f >>= (\<lambda>x. g x)) h) c"
  apply (rule ccorresI')
  apply (erule(3) ccorresE)
    defer
    apply assumption
   apply (subst alternative_left_readonly_bind, assumption)
    apply (rule notI, drule(1) empty_failD)
    apply (simp add: alternative_def bind_def)
   apply fastforce
  apply (subgoal_tac "\<forall>x \<in> fst (f s). snd x = s")
   apply (simp add: bind_def alternative_def image_image split_def
              cong: image_cong)
  apply clarsimp
  apply (drule use_valid, assumption, simp+)
  done

definition
  "pd_has_hwasid pd =
     (\<lambda>s. \<exists>v. asid_map_pd_to_hwasids (armKSASIDMap (ksArchState s)) pd = {v})"

lemma ccap_relation_pd_helper:
  "\<lbrakk> ccap_relation cap cap'; cap_get_tag cap' = scast cap_page_directory_cap \<rbrakk>
        \<Longrightarrow> capPDBasePtr_CL (cap_page_directory_cap_lift cap') = capPDBasePtr (capCap cap)"
  by (clarsimp simp: cap_lift_page_directory_cap cap_to_H_simps
                     cap_page_directory_cap_lift
              elim!: ccap_relationE)

lemma stored_hw_asid_get_ccorres_split':
  assumes  ptr: "ptr = CTypesDefs.ptr_add pd 0xFF0"
  assumes ceqv: "\<And>rv' t t'. ceqv Gamm stored_hw_asid___struct_pde_C_' rv' t t' c (c' rv')"
   and ccorres: "\<And>shw_asid. pde_get_tag shw_asid = scast pde_pde_invalid \<Longrightarrow>
                      ccorres_underlying rf_sr Gamm r xf ar axf
                                   (Q shw_asid) (R shw_asid) hs
                                   a (c' shw_asid)"
  shows "ccorres_underlying rf_sr Gamm r xf ar axf
                (\<lambda>s. page_directory_at' (ptr_val pd) s \<and> valid_pde_mappings' s
                      \<and> (\<forall>shw_asid. asid_map_pd_to_hwasids (armKSASIDMap (ksArchState s)) (ptr_val pd)
                               = set_option (pde_stored_asid shw_asid) \<and> pde_get_tag shw_asid = scast pde_pde_invalid
                             \<longrightarrow> P shw_asid \<and> Q shw_asid s))
                {s. \<forall>stored_hw_asid. P stored_hw_asid \<and> pde_get_tag stored_hw_asid = scast pde_pde_invalid
                            \<and> (cslift s \<circ>\<^sub>m pd_pointer_to_asid_slot) (ptr_val pd) = Some stored_hw_asid
                      \<longrightarrow> s \<lparr> stored_hw_asid___struct_pde_C_' := stored_hw_asid \<rparr>
                                 \<in> R stored_hw_asid} hs
                a (Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t ptr\<rbrace>
                       (\<acute>stored_hw_asid___struct_pde_C :==
                               h_val (hrs_mem \<acute>t_hrs) ptr);; c)"
  unfolding ptr
  apply (rule ccorres_guard_imp2)
   apply (rule ccorres_Guard_Seq)
   apply (rule ccorres_symb_exec_r)
     apply (rule ccorres_abstract_all[OF ceqv])
     apply (rule_tac A="\<lambda>s. asid_map_pd_to_hwasids (armKSASIDMap (ksArchState s)) (ptr_val pd)
                               = set_option (pde_stored_asid rv') \<and> pde_get_tag rv' = scast pde_pde_invalid
                            \<longrightarrow> P rv' \<and> Q rv' s"
                and A'="{s. P rv' \<longrightarrow> s \<in> R rv'}
                         \<inter> {s. (cslift s \<circ>\<^sub>m pd_pointer_to_asid_slot) (ptr_val pd)
                                  = Some rv' \<and> pde_get_tag rv' = scast pde_pde_invalid}"
                in ccorres_guard_imp2)
      apply (rule_tac P="pde_get_tag rv' = scast pde_pde_invalid" in ccorres_gen_asm)
      apply (erule ccorres)
     apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                           carch_state_relation_def
                           map_comp_Some_iff)
    apply vcg
   apply (rule conseqPre, vcg)
   apply clarsimp
  apply clarsimp
  apply (frule_tac x=pd_asid_slot in page_directory_pde_atI')
   apply (simp add: pd_asid_slot_def pageBits_def)
  apply (cases pd)
  apply (simp add: typ_at_to_obj_at_arches)
  apply (drule obj_at_ko_at')
  apply (clarsimp simp: pd_asid_slot_def)
  apply (erule cmap_relationE1[OF rf_sr_cpde_relation], erule ko_at_projectKO_opt)
  apply (frule(1) valid_pde_mappings_ko_atD')
  apply (clarsimp simp: typ_heap_simps' map_comp_Some_iff
                        valid_pde_mapping'_def)
  apply (clarsimp simp: pd_pointer_to_asid_slot_def page_directory_at'_def
                        add_mask_eq pdBits_def pageBits_def word_bits_def
                        valid_pde_mapping_offset'_def pd_asid_slot_def)
  apply (simp add: cpde_relation_def Let_def pde_lift_def
            split: split_if_asm)
  done

lemma ptr_add_0xFF0:
  "pde_Ptr (pd + 0x3FC0) = CTypesDefs.ptr_add (pde_Ptr pd) 0xFF0"
  by simp

lemmas stored_hw_asid_get_ccorres_split
    = stored_hw_asid_get_ccorres_split'[OF refl]
      stored_hw_asid_get_ccorres_split'[OF ptr_add_0xFF0]

lemma doMachineOp_pd_at_asid':
  "\<lbrace>\<lambda>s. P (pd_at_asid' pd asid s)\<rbrace> doMachineOp oper \<lbrace>\<lambda>rv s. P (pd_at_asid' pd asid s)\<rbrace>"
  apply (simp add: doMachineOp_def split_def)
  apply wp
  apply (clarsimp simp: pd_at_asid'_def)
  done

lemma doMachineOp_page_directory_at_P':
  "\<lbrace>\<lambda>s. P (page_directory_at' pd s)\<rbrace> doMachineOp oper \<lbrace>\<lambda>rv s. P (page_directory_at' pd s)\<rbrace>"
  apply (simp add: doMachineOp_def split_def)
  apply wp
  apply (clarsimp simp: pd_at_asid'_def)
  done

lemma pde_stored_asid_Some:
  "(pde_stored_asid pde = Some v)
     = (pde_get_tag pde = scast pde_pde_invalid
           \<and> to_bool (stored_asid_valid_CL (pde_pde_invalid_lift pde))
           \<and> v = ucast (stored_hw_asid_CL (pde_pde_invalid_lift pde)))"
  by (auto simp add: pde_stored_asid_def split: split_if)

lemma pointerInUserData_c_guard':
  "\<lbrakk> pointerInUserData ptr s; no_0_obj' s; is_aligned ptr 2 \<rbrakk>
   \<Longrightarrow> c_guard (Ptr ptr :: word32 ptr)"
  apply (simp add: pointerInUserData_def)
  apply (simp add: c_guard_def ptr_aligned_def)
  apply (rule conjI)
   apply (simp add: is_aligned_def)
  apply (simp add: c_null_guard_def)
  apply (subst intvl_aligned_bottom_eq[where n=2 and bits=2], simp_all)
  apply clarsimp
  done

lemma heap_relation_user_word_at_cross_over:
  "\<lbrakk> user_word_at x p s; cmap_relation (heap_to_page_data (ksPSpace s)
       (underlying_memory (ksMachineState s))) (cslift s') Ptr cuser_data_relation;
       p' = Ptr p \<rbrakk>
   \<Longrightarrow> c_guard p' \<and> hrs_htd (t_hrs_' (globals s')) \<Turnstile>\<^sub>t p'
         \<and> h_val (hrs_mem (t_hrs_' (globals s'))) p' = x"
  apply (erule cmap_relationE1)
   apply (clarsimp simp: heap_to_page_data_def Let_def
                         user_word_at_def pointerInUserData_def
                         typ_at_to_obj_at'[where 'a=user_data, simplified])
   apply (drule obj_at_ko_at', clarsimp)
   apply (rule conjI, rule exI, erule ko_at_projectKO_opt)
   apply (rule refl)
  apply (thin_tac "heap_to_page_data a b c = d" for a b c d)
  apply (cut_tac x=p and w="~~ mask pageBits" in word_plus_and_or_coroll2)
  apply (rule conjI)
   apply (clarsimp simp: user_word_at_def pointerInUserData_def)
   apply (simp add: c_guard_def c_null_guard_def ptr_aligned_def)
   apply (drule lift_t_g)
   apply (clarsimp simp: )
   apply (simp add: align_of_def user_data_C_size_of user_data_C_align_of
                    size_of_def user_data_C_typ_name)
   apply (fold is_aligned_def[where n=2, simplified], simp)
   apply (erule contra_subsetD[rotated])
   apply (rule order_trans[rotated])
    apply (rule_tac x="p && mask pageBits" and y=4 in intvl_sub_offset)
    apply (cut_tac y=p and a="mask pageBits && (~~ mask 2)" in word_and_le1)
    apply (subst(asm) word_bw_assocs[symmetric], subst(asm) aligned_neg_mask,
           erule is_aligned_andI1)
    apply (simp add: word_le_nat_alt mask_def pageBits_def)
   apply simp
  apply (clarsimp simp: cuser_data_relation_def user_word_at_def)
  apply (frule_tac f="[''words_C'']" in h_t_valid_field[OF h_t_valid_clift],
         simp+)
  apply (drule_tac n="uint (p && mask pageBits >> 2)" in h_t_valid_Array_element)
    apply simp
   apply (simp add: shiftr_over_and_dist mask_def pageBits_def uint_and)
   apply (insert int_and_leR [where a="uint (p >> 2)" and b=1023], clarsimp)[1]
  apply (simp add: field_lvalue_def
            field_lookup_offset_eq[OF trans, OF _ arg_cong[where f=Some, symmetric], OF _ pair_collapse]
            word32_shift_by_2 shiftr_shiftl1 is_aligned_neg_mask_eq is_aligned_andI1)
  apply (drule_tac x="ucast (p >> 2)" in spec)
  apply (simp add: byte_to_word_heap_def Let_def ucast_ucast_mask)
  apply (fold shiftl_t2n[where n=2, simplified, simplified mult.commute mult.left_commute])
  apply (simp add: aligned_shiftr_mask_shiftl pageBits_def)
  apply (rule trans[rotated], rule_tac hp="hrs_mem (t_hrs_' (globals s'))"
                                   and x="Ptr &(Ptr (p && ~~ mask 12) \<rightarrow> [''words_C''])"
                                    in access_in_array)
     apply (rule trans)
      apply (erule typ_heap_simps)
       apply simp+
    apply (rule order_less_le_trans, rule unat_lt2p)
    apply simp
   apply (fastforce simp add: typ_info_word)
  apply simp
  apply (rule_tac f="h_val hp" for hp in arg_cong)
  apply simp
  apply (simp add: field_lvalue_def)
  apply (simp add: ucast_nat_def ucast_ucast_mask)
  apply (fold shiftl_t2n[where n=2, simplified, simplified mult.commute mult.left_commute])
  apply (simp add: aligned_shiftr_mask_shiftl)
  done

lemma pointerInUserData_h_t_valid2:
  "\<lbrakk> pointerInUserData ptr s; cmap_relation (heap_to_page_data (ksPSpace s)
       (underlying_memory (ksMachineState s))) (cslift s') Ptr cuser_data_relation;
       is_aligned ptr 2 \<rbrakk>
      \<Longrightarrow> hrs_htd (t_hrs_' (globals s')) \<Turnstile>\<^sub>t (Ptr ptr :: word32 ptr)"
  apply (frule_tac p=ptr in
     heap_relation_user_word_at_cross_over[rotated, OF _ refl])
   apply (simp add: user_word_at_def)
  apply simp
  done

lemma dmo_clearExMonitor_setCurThread_swap:
  "(do _ \<leftarrow> doMachineOp MachineOps.clearExMonitor;
               setCurThread thread
            od)
    = (do _ \<leftarrow> setCurThread thread;
            doMachineOp MachineOps.clearExMonitor od)"
  apply (simp add: setCurThread_def doMachineOp_def split_def)
  apply (rule oblivious_modify_swap[symmetric])
  apply (intro oblivious_bind,
         simp_all add: select_f_oblivious)
  done

lemma ccorres_bind_assoc_rev:
  "ccorres_underlying sr E r xf arrel axf G G' hs ((a1 >>= a2) >>= a3) c
    \<Longrightarrow> ccorres_underlying sr E r xf arrel axf G G' hs
         (do x \<leftarrow> a1; y \<leftarrow> a2 x; a3 y od) c"
  by (simp add: bind_assoc)

lemma monadic_rewrite_gets_l:
  "(\<And>x. monadic_rewrite F E (P x) (g x) m)
    \<Longrightarrow> monadic_rewrite F E (\<lambda>s. P (f s) s) (gets f >>= (\<lambda>x. g x)) m"
  by (auto simp add: monadic_rewrite_def exec_gets)

lemma pd_at_asid_inj':
  "pd_at_asid' pd asid s \<Longrightarrow> pd_at_asid' pd' asid s \<Longrightarrow> pd' = pd"
  by (clarsimp simp: pd_at_asid'_def obj_at'_def)

lemma armv_contextSwitch_HWASID_fp_rewrite:
  "monadic_rewrite True False
    (pd_has_hwasid pd and pd_at_asid' pd asid and
        (\<lambda>s. asid_map_pd_to_hwasids (armKSASIDMap (ksArchState s)) pd
                                     = set_option (pde_stored_asid v)))
    (armv_contextSwitch pd asid)
    (doMachineOp (armv_contextSwitch_HWASID pd (the (pde_stored_asid v))))"
  apply (simp add: getHWASID_def armv_contextSwitch_def
                        bind_assoc loadHWASID_def
                        findPDForASIDAssert_def
                        checkPDAt_def checkPDUniqueToASID_def
                        checkPDASIDMapMembership_def
                        stateAssert_def2[folded assert_def])
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_gets_l)
   apply (rule monadic_rewrite_symb_exec_l)
      apply (wp | simp)+
     apply (simp add: empty_fail_findPDForASID empty_fail_catch)
    apply (rule monadic_rewrite_assert monadic_rewrite_gets_l)+
    apply (rule_tac P="x asid \<noteq> None \<and> fst (the (x asid)) = the (pde_stored_asid v)"
        in monadic_rewrite_gen_asm)
    apply (simp only: case_option_If2 simp_thms if_True if_False
                      split_def, simp)
    apply (rule monadic_rewrite_refl)
   apply (wp findPDForASID_pd_at_wp | simp only: const_def)+
  apply (clarsimp simp: pd_has_hwasid_def cte_level_bits_def
                        field_simps cte_wp_at_ctes_of
                        word_0_sle_from_less
                        isCap_simps invs_valid_pspace'
              simp del: Collect_const rf_sr_upd_safe)
  apply (drule(1) pd_at_asid_inj')
  apply (clarsimp simp: singleton_eq_o2s singleton_eq_o2s[THEN trans[OF eq_commute]])
  apply (cases "pde_stored_asid v", simp_all)
  apply (clarsimp simp: asid_map_pd_to_hwasids_def set_eq_subset
                 elim!: ranE)
  apply (case_tac "x = asid")
   apply clarsimp
  apply (erule notE, rule_tac a=x in ranI)
  apply simp
  done

lemma switchToThread_fp_ccorres:
  "ccorres dc xfdc (pspace_aligned' and pspace_distinct' and valid_objs' and no_0_obj'
                          and valid_pde_mappings' and valid_arch_state'
                          and tcb_at' thread
                          and cte_wp_at' (\<lambda>cte. isValidVTableRoot (cteCap cte)
                                              \<and> capPDBasePtr (capCap (cteCap cte)) = pd)
                                         (thread + tcbVTableSlot * 0x10)
                          and pd_has_hwasid pd
                          and (\<lambda>s. asid_map_pd_to_hwasids (armKSASIDMap (ksArchState s)) pd
                                     = set_option (pde_stored_asid v)))
                   (UNIV \<inter> {s. thread_' s = tcb_ptr_to_ctcb_ptr thread}
                         \<inter> {s. cap_pd_' s = pde_Ptr pd}
                         \<inter> {s. stored_hw_asid___struct_pde_C_' s = v}) []
      (ArchThreadDecls_H.switchToThread thread
            >>= (\<lambda>_. setCurThread thread))
      (Call switchToThread_fp_'proc)"
  apply (cinit' lift: thread_' cap_pd_' stored_hw_asid___struct_pde_C_')
   apply (simp add: ArchThread_H.switchToThread_def bind_assoc
                    setVMRoot_def cap_case_isPageDirectoryCap
               del: Collect_const cong: call_ignore_cong)
   apply (simp add: getThreadVSpaceRoot_def locateSlot_conv getSlotCap_def
               del: Collect_const cong: call_ignore_cong)
   apply (simp only: )
   apply (rule ccorres_symb_exec_r, rule_tac xf'="hw_asid_'" in ccorres_abstract,
          ceqv, rename_tac "hw_asid")
     apply (rule ccorres_getCTE, rename_tac cte)
     apply (rule_tac P="isValidVTableRoot (cteCap cte)
                        \<and> capPDBasePtr (capCap (cteCap cte)) = pd" in ccorres_gen_asm)
     apply (erule conjE, drule isValidVTableRootD)
     apply (simp del: Collect_const cong: call_ignore_cong)
     apply (rule ccorres_catch_bindE_symb_exec_l,
            rule findPDForASID_inv,
            rule empty_fail_findPDForASID)
       apply (rename_tac "pd_found")
       apply (rule_tac P="pd_found \<noteq> pd"
                    in ccorres_case_bools2)
        apply (simp add: bindE_assoc catch_liftE_bindE bind_assoc
                         checkPDNotInASIDMap_def
                         checkPDASIDMapMembership_def
                         catch_throwError)
        apply (rule ccorres_stateAssert)
        apply (rule ccorres_False[where P'=UNIV])
       apply (simp add: catch_liftE bind_assoc 
                   del: Collect_const cong: call_ignore_cong)
       apply (rule monadic_rewrite_ccorres_assemble[rotated])
        apply (rule monadic_rewrite_bind_head)
        apply (rule_tac pd=pd and v=v
                     in armv_contextSwitch_HWASID_fp_rewrite)
       apply (ctac(no_vcg) add: armv_contextSwitch_HWASID_ccorres)
        apply (simp add: storeWordUser_def bind_assoc case_option_If2
                         split_def
                    del: Collect_const)
        apply (rule ccorres_symb_exec_l[OF _ gets_inv _ empty_fail_gets])
         apply (rename_tac "gf")
         apply (rule ccorres_pre_threadGet)
         apply (rule ccorres_stateAssert)
         apply (rule_tac P="pointerInUserData gf and no_0_obj'
                               and K (is_aligned gf 2)
                               and (\<lambda>s. gf = armKSGlobalsFrame (ksArchState s))
                               and valid_arch_state'"
                in ccorres_cross_over_guard)
         apply (rule ccorres_Guard_Seq)
         apply (rule ccorres_Guard_Seq)
         apply (rule ccorres_move_c_guard_tcb)
         apply (ctac add: storeWord_ccorres'[unfolded fun_app_def])
           apply (simp only: dmo_clearExMonitor_setCurThread_swap
                             dc_def[symmetric])
           apply (rule ccorres_split_nothrow_novcg_dc)
              apply (rule ccorres_from_vcg[where P=\<top> and P'=UNIV])
              apply (rule allI, rule conseqPre, vcg)
              apply (clarsimp simp del: rf_sr_upd_safe)
              apply (clarsimp simp: setCurThread_def simpler_modify_def
                                    rf_sr_def cstate_relation_def Let_def
                                    carch_state_relation_def cmachine_state_relation_def)
             apply (ctac add: clearExMonitor_fp_ccorres)
            apply wp
           apply (simp add: guard_is_UNIV_def)
          apply wp
         apply vcg
        apply wp
        apply (simp add: obj_at'_weakenE[OF _ TrueI])
        apply (wp hoare_drop_imps)[1]
      apply (simp add: bind_assoc checkPDNotInASIDMap_def
                       checkPDASIDMapMembership_def)
      apply (rule ccorres_stateAssert)
      apply (rule ccorres_False[where P'=UNIV])
     apply simp
     apply (wp findPDForASID_pd_at_wp)[1]
    apply (simp del: Collect_const)
    apply vcg
   apply (rule conseqPre, vcg, clarsimp)
  apply (clarsimp simp: pd_has_hwasid_def cte_level_bits_def
                        field_simps cte_wp_at_ctes_of
                        pd_at_asid'_def word_0_sle_from_less
                        isCap_simps invs_valid_pspace'
              simp del: Collect_const rf_sr_upd_safe)
  apply (frule_tac P="\<lambda>Sf. Sf x = S'" for x S'
            in subst[OF meta_eq_to_obj_eq, OF asid_map_pd_to_hwasids_def])
  apply (clarsimp simp: isCap_simps dest!: isValidVTableRootD)
  apply (rule context_conjI)
   apply (drule singleton_eqD[OF sym])
   apply clarsimp
   apply (fastforce simp: ran_def)
  apply (frule ctes_of_valid', clarsimp, clarsimp simp: valid_cap'_def)
  apply (cut_tac s=s in is_aligned_globals_2_strg[rule_format])
   apply auto[1]
  apply (intro conjI impI)
      apply simp
     apply (clarsimp simp: singleton_eq_o2s projectKOs obj_at'_def)
    apply (clarsimp simp: singleton_eq_o2s projectKOs obj_at'_def
                          pde_stored_asid_def split: split_if_asm)
   apply (clarsimp simp: singleton_eq_o2s pde_stored_asid_def
                  split: if_splits)
  apply (clarsimp simp del: rf_sr_upd_safe
    dest!: isValidVTableRootD
    simp: cap_get_tag_isCap_ArchObject2 pde_stored_asid_Some
    rf_sr_asid_map_pd_to_hwasids option_set_singleton_eq
    map_comp_Some_iff)
  apply (clarsimp simp: typ_heap_simps' ctcb_relation_def
                        trans[OF eq_commute option_set_singleton_eq]
                        pde_stored_asid_Some
              simp del: rf_sr_upd_safe)
  apply (clarsimp simp: pde_stored_asid_def typ_heap_simps'
                        pointerInUserData_h_t_valid2
              simp del: rf_sr_upd_safe)
  apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def carch_state_relation_def
                        carch_globals_def pointerInUserData_c_guard'
                        pointerInUserData_h_t_valid2 cpspace_relation_def
                        c_guard_abs_word32_armKSGlobalsFrame)
  done

lemma thread_state_ptr_set_tsType_np_spec:
  defines "ptr s \<equiv> cparent \<^bsup>s\<^esup>ts_ptr [''tcbState_C''] :: tcb_C ptr"
  shows
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. hrs_htd \<^bsup>s\<^esup>t_hrs \<Turnstile>\<^sub>t ptr s
                 \<and> (tsType_' s = scast ThreadState_Running \<or> tsType_' s = scast ThreadState_Restart
                          \<or> tsType_' s = scast ThreadState_BlockedOnReply)\<rbrace>
              Call thread_state_ptr_set_tsType_np_'proc
       {t. (\<exists>thread_state.
               tsType_CL (thread_state_lift thread_state) = tsType_' s \<and>
               tcbQueued_CL (thread_state_lift thread_state)
                    = tcbQueued_CL (thread_state_lift (tcbState_C (the (cslift s (ptr s))))) \<and>
               cslift t = cslift s(ptr s \<mapsto> the (cslift s (ptr s))\<lparr>tcbState_C := thread_state\<rparr>))
           \<and> types_proofs.cslift_all_but_tcb_C t s
           \<and> hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))}"
  apply (intro allI, rule conseqPre, vcg)
  apply (clarsimp simp: ptr_def)
  apply (clarsimp simp: h_t_valid_clift_Some_iff)
  apply (frule h_t_valid_c_guard_cparent[OF h_t_valid_clift], simp+,
         simp add: typ_uinfo_t_def)
  apply (frule clift_subtype, simp+)
  apply (clarsimp simp: typ_heap_simps' word_sle_def word_sless_def)
  apply (subst parent_update_child, erule typ_heap_simps', simp+)
  apply (clarsimp simp: typ_heap_simps')
  apply (rule exI, rule conjI[OF _ conjI [OF _ refl]])
  apply (simp_all add: thread_state_lift_def)
  apply (auto simp: "StrictC'_thread_state_defs")
  done

lemma thread_state_ptr_mset_blockingIPCEndpoint_tsType_spec:
  defines "ptr s \<equiv> cparent \<^bsup>s\<^esup>ts_ptr [''tcbState_C''] :: tcb_C ptr"
  shows
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. hrs_htd \<^bsup>s\<^esup>t_hrs \<Turnstile>\<^sub>t ptr s \<and> is_aligned (ep_ref_' s) 4
                         \<and> tsType_' s && mask 4 = tsType_' s\<rbrace>
              Call thread_state_ptr_mset_blockingIPCEndpoint_tsType_'proc
       {t. (\<exists>thread_state.
               tsType_CL (thread_state_lift thread_state) = tsType_' s
             \<and> blockingIPCEndpoint_CL (thread_state_lift thread_state) = ep_ref_' s
             \<and> tcbQueued_CL (thread_state_lift thread_state)
                  = tcbQueued_CL (thread_state_lift (tcbState_C (the (cslift s (ptr s)))))
             \<and> cslift t = cslift s(ptr s \<mapsto> the (cslift s (ptr s))\<lparr>tcbState_C := thread_state\<rparr>))
             \<and> types_proofs.cslift_all_but_tcb_C t s
             \<and> hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))}"
  apply (intro allI, rule conseqPre, vcg)
  apply (clarsimp simp: ptr_def)
  apply (frule h_t_valid_c_guard_cparent, simp+)
   apply (simp add: typ_uinfo_t_def)
  apply (clarsimp simp: h_t_valid_clift_Some_iff)
  apply (frule clift_subtype, simp+)
  apply (clarsimp simp: typ_heap_simps')
  apply (subst parent_update_child, erule typ_heap_simps', simp+)
  apply (clarsimp simp: typ_heap_simps' word_sless_def word_sle_def)
  apply (rule exI, intro conjI[rotated], rule refl)
    apply (simp_all add: thread_state_lift_def word_ao_dist
                         is_aligned_mask mask_def mask_eq_0_eq_x,
           simp_all add: mask_eq_x_eq_0)
  done

lemma thread_state_ptr_set_blockingIPCDiminish_np_spec:
  defines "ptr s \<equiv> cparent \<^bsup>s\<^esup>ts_ptr [''tcbState_C''] :: tcb_C ptr"
  shows
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. hrs_htd \<^bsup>s\<^esup>t_hrs \<Turnstile>\<^sub>t ptr s \<and> dim_' s && 1 = dim_' s\<rbrace>
              Call thread_state_ptr_set_blockingIPCDiminish_np_'proc
       {t. \<exists>tcb ts. cslift s (ptr s) = Some tcb
             \<and> blockingIPCDiminishCaps_CL (thread_state_lift ts) = dim_' s
             \<and> tcbQueued_CL (thread_state_lift ts)
                  = tcbQueued_CL (thread_state_lift (tcbState_C tcb))
             \<and> tsType_CL (thread_state_lift ts)
                  = tsType_CL (thread_state_lift (tcbState_C tcb))
             \<and> blockingIPCEndpoint_CL (thread_state_lift ts)
                  = blockingIPCEndpoint_CL (thread_state_lift (tcbState_C tcb))
             \<and> cslift t = cslift s(ptr s \<mapsto> tcb\<lparr>tcbState_C := ts\<rparr>)
             \<and> types_proofs.cslift_all_but_tcb_C t s
             \<and> hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))}"
  apply (intro allI, rule conseqPre, vcg)
  apply (clarsimp simp: ptr_def)
  apply (frule h_t_valid_c_guard_cparent, simp+)
   apply (simp add: typ_uinfo_t_def)
  apply (clarsimp simp: h_t_valid_clift_Some_iff)
  apply (frule clift_subtype, simp+)
  apply (clarsimp simp: typ_heap_simps')
  apply (subst parent_update_child, erule typ_heap_simps', simp+)
  apply (clarsimp simp: typ_heap_simps' word_sle_def)
  apply (rule exI, intro conjI[rotated], rule refl)
     apply (simp_all add: thread_state_lift_def)
  done

lemma mdb_node_ptr_mset_mdbNext_mdbRevocable_mdbFirstBadged_spec:
  defines "ptr s \<equiv> cparent \<^bsup>s\<^esup>node_ptr [''cteMDBNode_C''] :: cte_C ptr"
  shows
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. hrs_htd \<^bsup>s\<^esup>t_hrs \<Turnstile>\<^sub>t ptr s \<and> is_aligned (mdbNext_' s) 4
                         \<and> mdbRevocable_' s && mask 1 = mdbRevocable_' s
                         \<and> mdbFirstBadged_' s && mask 1 = mdbFirstBadged_' s\<rbrace>
              Call mdb_node_ptr_mset_mdbNext_mdbRevocable_mdbFirstBadged_'proc
       {t. (\<exists>mdb_node.
               mdb_node_lift mdb_node = mdb_node_lift (cteMDBNode_C (the (cslift s (ptr s))))
                           \<lparr> mdbNext_CL := mdbNext_' s, mdbRevocable_CL := mdbRevocable_' s,
                             mdbFirstBadged_CL := mdbFirstBadged_' s \<rparr>
             \<and> cslift t = cslift s(ptr s \<mapsto> the (cslift s (ptr s)) \<lparr> cteMDBNode_C := mdb_node \<rparr>))
             \<and> types_proofs.cslift_all_but_cte_C t s
             \<and> hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))}"
  apply (intro allI, rule conseqPre, vcg)
  apply (clarsimp simp: ptr_def)
  apply (clarsimp simp: h_t_valid_clift_Some_iff)
  apply (frule h_t_valid_c_guard_cparent[OF h_t_valid_clift], simp+,
         simp add: typ_uinfo_t_def)
  apply (frule clift_subtype, simp+)
  apply (clarsimp simp: typ_heap_simps' word_sle_def word_sless_def)
  apply (subst parent_update_child, erule typ_heap_simps', simp+)
  apply (clarsimp simp: typ_heap_simps')
  apply (rule exI, rule conjI[OF _ refl])
  apply (simp add: mdb_node_lift_def word_ao_dist shiftr_over_or_dist)
  apply (fold limited_and_def)
  apply (simp add: limited_and_simps)
  done


lemma mdb_node_ptr_set_mdbPrev_np_spec:
  defines "ptr s \<equiv> cparent \<^bsup>s\<^esup>node_ptr [''cteMDBNode_C''] :: cte_C ptr"
  shows
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. hrs_htd \<^bsup>s\<^esup>t_hrs \<Turnstile>\<^sub>t ptr s \<and> is_aligned (mdbPrev_' s) 4\<rbrace>
              Call mdb_node_ptr_set_mdbPrev_np_'proc
       {t. (\<exists>mdb_node.
               mdb_node_lift mdb_node = mdb_node_lift (cteMDBNode_C (the (cslift s (ptr s))))
                           \<lparr> mdbPrev_CL := mdbPrev_' s \<rparr>
             \<and> cslift t = cslift s(ptr s \<mapsto> the (cslift s (ptr s)) \<lparr> cteMDBNode_C := mdb_node \<rparr>))
             \<and> types_proofs.cslift_all_but_cte_C t s
             \<and> hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))}"
  apply (intro allI, rule conseqPre, vcg)
  apply (clarsimp simp: ptr_def)
  apply (clarsimp simp: h_t_valid_clift_Some_iff)
  apply (frule h_t_valid_c_guard_cparent[OF h_t_valid_clift], simp+,
         simp add: typ_uinfo_t_def)
  apply (frule clift_subtype, simp+)
  apply (clarsimp simp: typ_heap_simps')
  apply (subst parent_update_child, erule typ_heap_simps', simp+)
  apply (clarsimp simp: typ_heap_simps' word_sle_def word_sless_def)
  apply (rule exI, rule conjI [OF _ refl])
  apply (simp add: mdb_node_lift_def limited_and_simps)
  done

lemma cap_reply_cap_ptr_new_np_spec2:
  defines "ptr s \<equiv> cparent \<^bsup>s\<^esup>cap_ptr [''cap_C''] :: cte_C ptr"
  shows
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. hrs_htd \<^bsup>s\<^esup>t_hrs \<Turnstile>\<^sub>t ptr s \<and> is_aligned (capTCBPtr_' s) 8
                    \<and> capReplyMaster_' s && 1 = capReplyMaster_' s\<rbrace>
              Call cap_reply_cap_ptr_new_np_'proc
       {t. (\<exists>cap.
               cap_lift cap = Some (Cap_reply_cap \<lparr> capReplyMaster_CL = capReplyMaster_' s,
                                                         capTCBPtr_CL = capTCBPtr_' s \<rparr>)
             \<and> cslift t = cslift s(ptr s \<mapsto> the (cslift s (ptr s)) \<lparr> cte_C.cap_C := cap \<rparr>))
             \<and> types_proofs.cslift_all_but_cte_C t s
             \<and> hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))}"
  apply (intro allI, rule conseqPre, vcg)
  apply (clarsimp simp: ptr_def)
  apply (clarsimp simp: h_t_valid_clift_Some_iff word_sle_def)
  apply (frule h_t_valid_c_guard_cparent[OF h_t_valid_clift],
         simp+, simp add: typ_uinfo_t_def)
  apply (frule clift_subtype, simp+)
  apply (clarsimp simp: typ_heap_simps')
  apply (subst parent_update_child, erule typ_heap_simps', simp+)
  apply (clarsimp simp: typ_heap_simps' word_sless_def word_sle_def)
  apply (rule exI, rule conjI [OF _ refl])
  apply (fold limited_and_def)
  apply (simp add: cap_get_tag_def mask_def cap_tag_defs
                   word_ao_dist limited_and_simps
                   cap_lift_reply_cap shiftr_over_or_dist)
  done

lemma endpoint_ptr_mset_epQueue_tail_state_spec:
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. hrs_htd \<^bsup>s\<^esup>t_hrs \<Turnstile>\<^sub>t ep_ptr_' s \<and> is_aligned (epQueue_tail_' s) 4
                         \<and> state_' s && mask 2 = state_' s\<rbrace>
              Call endpoint_ptr_mset_epQueue_tail_state_'proc
       {t. (\<exists>endpoint.
               endpoint_lift endpoint = endpoint_lift (the (cslift s (ep_ptr_' s)))
                           \<lparr> endpoint_CL.state_CL := state_' s, epQueue_tail_CL := epQueue_tail_' s \<rparr>
             \<and> cslift t = cslift s(ep_ptr_' s \<mapsto> endpoint))
             \<and> types_proofs.cslift_all_but_endpoint_C t s
             \<and> hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))}"
  apply (intro allI, rule conseqPre, vcg)
  apply (clarsimp simp: h_t_valid_clift_Some_iff typ_heap_simps'
                        word_sle_def word_sless_def)
  apply (rule exI, rule conjI[OF _ refl])
  apply (simp add: endpoint_lift_def word_ao_dist
                   mask_def)
  apply (fold limited_and_def)
  apply (simp add: limited_and_simps)
  done

lemma endpoint_ptr_set_epQueue_head_np_spec:
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. hrs_htd \<^bsup>s\<^esup>t_hrs \<Turnstile>\<^sub>t ep_ptr_' s \<and> is_aligned (epQueue_head_' s) 4\<rbrace>
              Call endpoint_ptr_set_epQueue_head_np_'proc
       {t. (\<exists>endpoint.
               endpoint_lift endpoint = endpoint_lift (the (cslift s (ep_ptr_' s)))
                           \<lparr> epQueue_head_CL := epQueue_head_' s \<rparr>
             \<and> cslift t = cslift s(ep_ptr_' s \<mapsto> endpoint))
             \<and> types_proofs.cslift_all_but_endpoint_C t s
             \<and> hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))}"
  apply (intro allI, rule conseqPre, vcg)
  apply (clarsimp simp: h_t_valid_clift_Some_iff typ_heap_simps'
                        word_sless_def word_sle_def)
  apply (rule exI, rule conjI[OF _ refl])
  apply (simp add: endpoint_lift_def word_ao_dist
                   mask_def)
  apply (simp add: limited_and_simps)
  done

lemmas empty_fail_user_getreg = empty_fail_asUser[OF empty_fail_getRegister]

lemma empty_fail_getCurThread[iff]:
  "empty_fail getCurThread" by (simp add: getCurThread_def)

lemma ccorres_call_hSkip':
  assumes  cul: "ccorres_underlying sr \<Gamma> r xf' r xf' P (i ` P') [SKIP] a (Call f)"
  and      gsr: "\<And>a b x s t. (x, t) \<in> sr \<Longrightarrow> (x, g a b (clean s t)) \<in> sr"
  and      csr: "\<And>x s t. (x, t) \<in> sr \<Longrightarrow> (x, clean s t) \<in> sr"
  and      res: "\<And>a s t rv. r rv (xf' t) \<Longrightarrow> r rv (xf (g a t (clean s t)))"
  and     ares: "\<And>s t rv. r rv (xf' t) \<Longrightarrow> r rv (xf (clean s t))"
  and      ist: "\<And>x s. (x, s) \<in> sr \<Longrightarrow> (x, i s) \<in> sr"
  shows "ccorres_underlying sr \<Gamma> r xf r xf P P' [SKIP] a (call i f clean (\<lambda>x y. Basic (g x y)))"
  apply (rule ccorresI')
  apply (erule exec_handlers.cases, simp_all)[1]
   apply clarsimp
   apply (erule exec_call_Normal_elim, simp_all)[1]
    apply (clarsimp elim!: exec_Normal_elim_cases)
   apply (rule ccorresE[OF cul ist], assumption+, simp+)
    apply (rule EHAbrupt)
     apply (erule(1) exec.Call)
    apply (rule EHOther, rule exec.Skip, simp)
   apply clarsimp
   apply (erule exec_handlers.cases, simp_all)[1]
    apply (clarsimp elim!: exec_Normal_elim_cases)
   apply (clarsimp elim!: exec_Normal_elim_cases)
   apply (erule rev_bexI)
   apply (simp add: unif_rrel_simps csr ares)
  apply clarsimp
  apply (erule exec_call_Normal_elim, simp_all)[1]
     apply (clarsimp elim!: exec_Normal_elim_cases)
     apply (rule ccorresE[OF cul ist], assumption+, simp+)
      apply (rule EHOther, erule(1) exec.Call)
      apply simp
     apply (simp add: unif_rrel_simps)
     apply (erule rev_bexI)
     apply (simp add: gsr res)
    apply (rule ccorresE[OF cul ist], assumption+, simp+)
     apply (rule EHOther, erule(1) exec.Call)
     apply simp
    apply simp
   apply (rule ccorresE[OF cul ist], assumption+, simp+)
    apply (rule EHOther, erule(1) exec.Call)
    apply simp
   apply simp
  apply (rule ccorresE[OF cul ist], assumption+, simp+)
   apply (rule EHOther, erule exec.CallUndefined)
   apply simp
  apply simp
  done

(* The naming convention here is that xf', xfr, and xfru are the terms we instantiate *)
lemma ccorres_call_hSkip:
  assumes  cul: "ccorres_underlying rf_sr \<Gamma> r xfdc r xfdc A C' [SKIP] a (Call f)"
  and      ggl: "\<And>x y s. globals (g x y s) = globals s"
  and      igl: "\<And>s. globals (i s) = globals s"
  shows "ccorres_underlying rf_sr \<Gamma> r xfdc r xfdc
          A {s. i s \<in> C'} [SKIP] a (call i f (\<lambda>s t. s\<lparr>globals := globals t\<rparr>) (\<lambda>x y. Basic (g x y)))"
  using cul
  unfolding rf_sr_def
  apply -
  apply (rule ccorres_call_hSkip')
       apply (erule ccorres_guard_imp)
        apply simp
       apply clarsimp
      apply (simp_all add: ggl xfdc_def)
  apply (clarsimp simp: igl)
  done

lemma bind_case_sum_rethrow:
  "rethrowFailure fl f >>= case_sum e g
     = f >>= case_sum (e \<circ> fl) g"
  apply (simp add: rethrowFailure_def handleE'_def
                   bind_assoc)
  apply (rule bind_cong[OF refl])
  apply (simp add: throwError_bind split: sum.split)
  done

lemma ccorres_alt_rdonly_liftE_bindE:
  "\<lbrakk> ccorres_underlying sr Gamm r xf arrel axf A A' hs
              (f >>= (\<lambda>x. alternative (g x) h)) c;
       \<And>s. \<lbrace>op = s\<rbrace> f \<lbrace>\<lambda>rv. op = s\<rbrace>; empty_fail f \<rbrakk>
   \<Longrightarrow> ccorres_underlying sr Gamm r xf arrel axf A A' hs
              (alternative (liftE f >>=E (\<lambda>x. g x)) h) c"
  by (simp add: liftE_bindE ccorres_alt_rdonly_bind)

lemma ccorres_pre_getCTE2:
  "(\<And>rv. ccorresG rf_sr \<Gamma> r xf (P rv) (P' rv) hs (f rv) c) \<Longrightarrow>
   ccorresG rf_sr \<Gamma> r xf (\<lambda>s. \<forall>cte. ctes_of s p = Some cte \<longrightarrow> P cte s)
                         {s. \<forall>cte cte'. cslift s (cte_Ptr p) = Some cte' \<and> ccte_relation cte cte'
                                          \<longrightarrow> s \<in> P' cte} hs
         (getCTE p >>= (\<lambda>rv. f rv)) c"
  apply (rule ccorres_guard_imp2, erule ccorres_pre_getCTE)
  apply (clarsimp simp: map_comp_Some_iff ccte_relation_def
                        c_valid_cte_def cl_valid_cte_def
                        c_valid_cap_def)
  done

declare empty_fail_assertE[iff]

declare empty_fail_resolveAddressBits[iff]

lemma ccap_relation_ep_helpers:
  "\<lbrakk> ccap_relation cap cap'; cap_get_tag cap' = scast cap_endpoint_cap \<rbrakk>
        \<Longrightarrow> capCanSend_CL (cap_endpoint_cap_lift cap') = from_bool (capEPCanSend cap)
          \<and> capCanReceive_CL (cap_endpoint_cap_lift cap') = from_bool (capEPCanReceive cap)
          \<and> capEPPtr_CL (cap_endpoint_cap_lift cap') = capEPPtr cap
          \<and> capEPBadge_CL (cap_endpoint_cap_lift cap') = capEPBadge cap
          \<and> capCanGrant_CL (cap_endpoint_cap_lift cap') = from_bool (capEPCanGrant cap)"
  by (clarsimp simp: cap_lift_endpoint_cap cap_to_H_simps
                     cap_endpoint_cap_lift_def word_size
                     from_bool_to_bool_and_1
              elim!: ccap_relationE)

lemma lookupExtraCaps_null:
  "msgExtraCaps info = 0 \<Longrightarrow>
     lookupExtraCaps thread buffer info = returnOk []"
  by (clarsimp simp: lookupExtraCaps_def
                     getExtraCPtrs_def liftE_bindE
                     upto_enum_step_def mapM_Nil
              split: Types_H.message_info.split option.split)

lemma fastpath_mi_check:
  "((mi && mask 9) + 3) && ~~ mask 3 = 0
      = (msgExtraCaps (messageInfoFromWord mi) = 0
            \<and> msgLength (messageInfoFromWord mi) \<le> scast n_msgRegisters
            \<and> msgLength_CL (message_info_lift (message_info_C (FCP (K mi))))
                  \<le> scast n_msgRegisters)"
  (is "?P = (?Q \<and> ?R \<and> ?S)")
proof -
  have le_Q: "?P = (?Q \<and> ?S)"
    apply (simp add: mask_def messageInfoFromWord_def Let_def
                     msgExtraCapBits_def msgLengthBits_def
                     message_info_lift_def fcp_beta n_msgRegisters_def)
    apply word_bitwise
    apply blast
    done
  have Q_R: "?S \<Longrightarrow> ?R"
    apply (clarsimp simp: messageInfoFromWord_def Let_def msgLengthBits_def
                          msgExtraCapBits_def mask_def n_msgRegisters_def
                          message_info_lift_def fcp_beta)
    apply (subst if_not_P, simp_all)
    apply (simp add: msgMaxLength_def linorder_not_less)
    apply (erule order_trans, simp)
    done
  from le_Q Q_R show ?thesis
    by blast
qed

lemma messageInfoFromWord_raw_spec:
  "\<forall>s. \<Gamma>\<turnstile> {s} Call messageInfoFromWord_raw_'proc
       \<lbrace>\<acute>ret__struct_message_info_C
    = (message_info_C (FCP (K \<^bsup>s\<^esup>w)))\<rbrace>"
  apply vcg
  apply (clarsimp simp: word_sless_def word_sle_def)
  apply (case_tac v)
  apply (simp add: cart_eq fcp_beta)
  done

lemma mi_check_messageInfo_raw:
  "msgLength_CL (message_info_lift (message_info_C (FCP (K mi))))
                  \<le> scast n_msgRegisters
    \<Longrightarrow> message_info_lift (message_info_C (FCP (K mi)))
        = mi_from_H (messageInfoFromWord mi)"
  apply (simp add: messageInfoFromWord_def Let_def mi_from_H_def
                   message_info_lift_def fcp_beta msgLengthBits_def msgExtraCapBits_def
                   msgMaxExtraCaps_def shiftL_nat)
  apply (subst if_not_P)
   apply (simp add: linorder_not_less msgMaxLength_def n_msgRegisters_def)
   apply (erule order_trans, simp)
  apply simp
  apply (thin_tac "P" for P)
  apply word_bitwise
  done

lemma fastpath_mi_check_spec:
  "\<forall>s. \<Gamma> \<turnstile> \<lbrace>s. True\<rbrace> Call fastpath_mi_check_'proc
           \<lbrace>(\<acute>ret__int = 0) = (msgExtraCaps (messageInfoFromWord \<^bsup>s\<^esup>msgInfo) = 0
              \<and> msgLength (messageInfoFromWord \<^bsup>s\<^esup>msgInfo) \<le> scast n_msgRegisters
              \<and> message_info_lift (message_info_C (FCP (K \<^bsup>s\<^esup>msgInfo)))
                  = mi_from_H (messageInfoFromWord \<^bsup>s\<^esup>msgInfo))\<rbrace>"
  apply (rule allI, rule conseqPre, vcg)
  apply (clarsimp simp: seL4_MsgLengthBits_def seL4_MsgExtraCapBits_def
                        word_sle_def if_1_0_0)
  apply (cut_tac mi="msgInfo_' s" in fastpath_mi_check)
  apply (simp add: mask_def)
  apply (auto intro: mi_check_messageInfo_raw[unfolded K_def])
  done

lemma isValidVTableRoot_fp_lemma:
  "(index (cap_C.words_C ccap) 0 && 0x1F = 0x10 || scast cap_page_directory_cap)
            = isValidVTableRoot_C ccap"
  apply (simp add: isValidVTableRoot_C_def ArchVSpace_H.isValidVTableRoot_def
                   cap_case_isPageDirectoryCap if_bool_simps)
  apply (subst split_word_eq_on_mask[where m="mask 4"])
  apply (simp add: mask_def word_bw_assocs word_ao_dist cap_page_directory_cap_def)
  apply (subgoal_tac "cap_get_tag ccap = scast cap_page_directory_cap
                  \<Longrightarrow> (index (cap_C.words_C ccap) 0 && 0x10 = 0x10) = to_bool (capPDIsMapped_CL (cap_page_directory_cap_lift ccap))")
   apply (clarsimp simp add: cap_get_tag_eq_x mask_def
                             cap_page_directory_cap_def split: split_if)
   apply (rule conj_cong[OF refl])
   apply clarsimp
  apply (clarsimp simp: cap_lift_page_directory_cap
                        cap_to_H_simps
                        to_bool_def bool_mask[folded word_neq_0_conv]
                        cap_page_directory_cap_lift_def
                 elim!: ccap_relationE split: split_if)
  apply (thin_tac "P" for P)
  apply word_bitwise
  done

lemma isValidVTableRoot_fp_spec:
  "\<forall>s. \<Gamma> \<turnstile> {s} Call isValidVTableRoot_fp_'proc
       {t. ret__unsigned_long_' t = from_bool (isValidVTableRoot_C (pd_cap_' s))}"
  apply vcg
  apply (clarsimp simp: word_sle_def word_sless_def isValidVTableRoot_fp_lemma)
  apply (simp add: from_bool_def split: split_if)
  done

lemma isRecvEP_endpoint_case:
  "isRecvEP ep \<Longrightarrow> case_endpoint f g h ep = f (epQueue ep)"
  by (clarsimp simp: isRecvEP_def split: endpoint.split_asm)

lemma ccorres_cond_both_seq:
  "\<lbrakk> \<forall>s s'. (s, s') \<in> sr \<and> R s \<longrightarrow> P s = (s' \<in> P');
     ccorres_underlying sr \<Gamma> r xf arrel axf Pt Rt hs a (c ;; d);
     ccorres_underlying sr \<Gamma> r xf arrel axf Pf Rf hs a (c' ;; d) \<rbrakk>
     \<Longrightarrow> ccorres_underlying sr \<Gamma> r xf arrel axf
         (R and (\<lambda>s. P s \<longrightarrow> Pt s) and (\<lambda>s. \<not> P s \<longrightarrow> Pf s))
         {s. (s \<in> P' \<longrightarrow> s \<in> Rt) \<and> (s \<notin> P' \<longrightarrow> s \<in> Rf)}
         hs a (Cond P' c c' ;; d)"
  apply (subst ccorres_seq_cond_raise)
  apply (rule ccorres_guard_imp2, rule ccorres_cond_both, assumption+)
  apply auto
  done

lemma copyMRs_simple:
  "msglen \<le> of_nat (length State_H.msgRegisters) \<longrightarrow>
    copyMRs sender sbuf receiver rbuf msglen
        = forM_x (take (unat msglen) State_H.msgRegisters)
             (\<lambda>r. do v \<leftarrow> asUser sender (getRegister r);
                    asUser receiver (setRegister r v) od)
           >>= (\<lambda>rv. return msglen)"
  apply (clarsimp simp: copyMRs_def mapM_discarded)
  apply (rule bind_cong[OF refl])
  apply (simp add: length_msgRegisters n_msgRegisters_def min_def
                   word_le_nat_alt
            split: option.split)
  apply (simp add: upto_enum_def mapM_Nil)
  done

lemma unifyFailure_catch_If:
  "catch (unifyFailure f >>=E g) h
     = f >>= (\<lambda>rv. if isRight rv then catch (g (theRight rv)) h else h ())"
  apply (simp add: unifyFailure_def rethrowFailure_def
                   handleE'_def catch_def bind_assoc
                   bind_bindE_assoc cong: if_cong)
  apply (rule bind_cong[OF refl])
  apply (simp add: throwError_bind isRight_def return_returnOk
            split: sum.split)
  done

end

abbreviation "tcb_Ptr_Ptr \<equiv> (Ptr :: word32 \<Rightarrow> tcb_C ptr ptr)"

abbreviation(input)
  "ptr_basic_update ptrfun vfun
      \<equiv> Basic (\<lambda>s. globals_update (t_hrs_'_update (hrs_mem_update
                    (heap_update (ptrfun s) (vfun s)))) s)"

context kernel_m begin

lemma fastpath_dequeue_ccorres:
  "dest1 = dest2 \<and> dest2 = tcb_ptr_to_ctcb_ptr dest \<and> ep_ptr1 = ep_Ptr ep_ptr \<Longrightarrow>
   ccorres dc xfdc
       (ko_at' (RecvEP (dest # xs)) ep_ptr and invs')
            {s. dest2 = tcb_ptr_to_ctcb_ptr dest
               \<and> dest1 = tcb_ptr_to_ctcb_ptr dest
               \<and> ep_ptr1 = ep_Ptr ep_ptr} hs
   (setEndpoint ep_ptr (case xs of [] \<Rightarrow> IdleEP | _ \<Rightarrow> RecvEP xs))
   (Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t dest1\<rbrace>
     (CALL endpoint_ptr_set_epQueue_head_np(ep_ptr1,ptr_val (h_val (hrs_mem \<acute>t_hrs) (tcb_Ptr_Ptr &(dest2\<rightarrow>[''tcbEPNext_C''])))));;
      Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t dest1\<rbrace>
     (IF h_val (hrs_mem \<acute>t_hrs) (tcb_Ptr_Ptr &(dest1\<rightarrow>[''tcbEPNext_C''])) \<noteq> tcb_Ptr 0 THEN
      Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t h_val (hrs_mem \<acute>t_hrs) (tcb_Ptr_Ptr &(dest1\<rightarrow>[''tcbEPNext_C'']))\<rbrace>
       (Guard C_Guard {s. s \<Turnstile>\<^sub>c dest1} (
       (ptr_basic_update (\<lambda>s. tcb_Ptr_Ptr &(h_val (hrs_mem (t_hrs_' (globals s)))
                                (tcb_Ptr_Ptr &(dest1\<rightarrow>[''tcbEPNext_C'']))\<rightarrow>[''tcbEPPrev_C''])) (\<lambda>_. NULL))))
      ELSE
        CALL endpoint_ptr_mset_epQueue_tail_state(ep_ptr1,scast 0,scast EPState_Idle)
      FI))"
  unfolding setEndpoint_def
  apply (rule setObject_ccorres_helper[rotated])
    apply simp
   apply (simp add: objBits_simps)
  apply (rule conseqPre, vcg)
  apply clarsimp
  apply (drule(1) ko_at_obj_congD')
  apply (frule ko_at_valid_ep', clarsimp)
  apply (rule cmap_relationE1[OF cmap_relation_ep], assumption,
         erule ko_at_projectKO_opt)
  apply (clarsimp simp: typ_heap_simps' valid_ep'_def
                        isRecvEP_endpoint_case neq_Nil_conv)
  apply (drule(1) obj_at_cslift_tcb)
  apply (clarsimp simp: typ_heap_simps')
  apply (case_tac "xs")
   apply (clarsimp simp: cendpoint_relation_def Let_def
                         isRecvEP_endpoint_case
                         tcb_queue_relation'_def
                         typ_heap_simps' endpoint_state_defs)
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def)
   apply (rule conjI)
    apply (clarsimp simp: cpspace_relation_def update_ep_map_tos)
    apply (erule(1) cpspace_relation_ep_update_ep2)
     apply (simp add: cendpoint_relation_def endpoint_state_defs)
    apply simp
   apply (simp add: carch_state_relation_def cmachine_state_relation_def
                    h_t_valid_clift_Some_iff)
  apply (clarsimp simp: neq_Nil_conv cendpoint_relation_def Let_def
                        isRecvEP_endpoint_case tcb_queue_relation'_def
                        typ_heap_simps' endpoint_state_defs)
  apply (clarsimp simp: is_aligned_weaken[OF is_aligned_tcb_ptr_to_ctcb_ptr]
                        tcb_at_not_NULL)
  apply (drule(1) obj_at_cslift_tcb)+
  apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def)
  apply (rule conjI)
   apply (clarsimp simp: cpspace_relation_def update_ep_map_tos
                         update_tcb_map_tos typ_heap_simps')
   apply (rule conjI, erule ctcb_relation_null_queue_ptrs)
    apply (rule ext, simp add: tcb_null_queue_ptrs_def
                        split: split_if)
   apply (rule conjI)
    apply (rule cpspace_relation_ep_update_ep, assumption+)
     apply (simp add: Let_def cendpoint_relation_def EPState_Recv_def)
     apply (simp add: tcb_queue_relation'_def tcb_queue_update_other)
    apply (simp add: isRecvEP_def)
   apply (erule iffD1 [OF cmap_relation_cong, OF refl refl, rotated -1])
   apply simp
   apply (rule casync_endpoint_relation_ep_queue [OF invs_sym'], assumption+)
     apply (simp add: isRecvEP_def)
    apply simp
   apply (erule (1) map_to_ko_atI')
  apply (simp add: carch_state_relation_def typ_heap_simps'
                   cmachine_state_relation_def h_t_valid_clift_Some_iff)
  apply (erule cready_queues_relation_null_queue_ptrs)
  apply (rule ext, simp add: tcb_null_ep_ptrs_def split: split_if)
  done

lemma tcb_NextPrev_C_update_swap:
  "tcbEPPrev_C_update f (tcbEPNext_C_update g tcb)
     = tcbEPNext_C_update g (tcbEPPrev_C_update f tcb)"
  by simp

lemma st_tcb_at_not_in_ep_queue:
  "\<lbrakk> st_tcb_at' P t s; ko_at' ep epptr s; sym_refs (state_refs_of' s);
     ep \<noteq> IdleEP; \<And>ts. P ts \<Longrightarrow> tcb_st_refs_of' ts = {} \<rbrakk>
      \<Longrightarrow> t \<notin> set (epQueue ep)"
  apply clarsimp
  apply (drule(1) sym_refs_ko_atD')
  apply (cases ep, simp_all add: st_tcb_at_refs_of_rev')
   apply (fastforce simp: st_tcb_at'_def obj_at'_def projectKOs)+
  done

lemma st_tcb_at_not_in_aep_queue:
  "\<lbrakk> st_tcb_at' P t s; ko_at' (WaitingAEP xs) aepptr s; sym_refs (state_refs_of' s);
     \<And>ts. P ts \<Longrightarrow> (aepptr, TCBAsync) \<notin> tcb_st_refs_of' ts \<rbrakk>
      \<Longrightarrow> t \<notin> set xs"
  apply (drule(1) sym_refs_ko_atD')
  apply (clarsimp simp: st_tcb_at_refs_of_rev')
  apply (fastforce simp: st_tcb_at'_def obj_at'_def projectKOs)
  done

lemma casync_relation_double_fun_upd:
  "\<lbrakk> casync_endpoint_relation mp aep aep'
       = casync_endpoint_relation (mp(a := b)) aep aep';
     casync_endpoint_relation (mp(a := b)) aep aep'
       = casync_endpoint_relation (mp(a := b, c := d)) aep aep' \<rbrakk>
   \<Longrightarrow> casync_endpoint_relation mp aep aep'
         = casync_endpoint_relation (mp(a := b, c := d)) aep aep'"
  by simp

lemma sym_refs_upd_ko_atD':
  "\<lbrakk> ko_at' ko p s; sym_refs ((state_refs_of' s) (p' := S)); p \<noteq> p' \<rbrakk>
      \<Longrightarrow> \<forall>(x, tp) \<in> refs_of' (injectKO ko). (x = p' \<and> (p, symreftype tp) \<in> S)
                 \<or> (x \<noteq> p' \<and> ko_wp_at' (\<lambda>ko. (p, symreftype tp) \<in> refs_of' ko)x s)"
  apply (clarsimp del: disjCI)
  apply (drule ko_at_state_refs_ofD')
  apply (drule_tac y=a and tp=b and x=p in sym_refsD[rotated])
   apply simp
  apply (case_tac "a = p'")
   apply simp
  apply simp
  apply (erule state_refs_of'_elemD)
  done

lemma sym_refs_upd_sD:
  "\<lbrakk> sym_refs ((state_refs_of' s) (p := S)); valid_pspace' s;
            ko_at' ko p s; refs_of' (injectKO koEx) = S;
            objBits koEx = objBits ko \<rbrakk>
      \<Longrightarrow> \<exists>s'. sym_refs (state_refs_of' s')
               \<and> (\<forall>p' (ko' :: endpoint). ko_at' ko' p' s \<and> injectKO ko' \<noteq> injectKO ko
                          \<longrightarrow> ko_at' ko' p' s')
               \<and> (\<forall>p' (ko' :: async_endpoint). ko_at' ko' p' s \<and> injectKO ko' \<noteq> injectKO ko
                          \<longrightarrow> ko_at' ko' p' s')
               \<and> (ko_at' koEx p s')"
  apply (rule exI, rule conjI)
   apply (rule state_refs_of'_upd[where ko'="injectKO koEx" and ptr=p and s=s,
                                  THEN ssubst[where P=sym_refs], rotated 2])
     apply simp+
   apply (clarsimp simp: obj_at'_def ko_wp_at'_def projectKOs)
   apply (clarsimp simp: project_inject objBits_def)
  apply (clarsimp simp: obj_at'_def ps_clear_upd projectKOs
                 split: split_if)
  apply (clarsimp simp: project_inject objBits_def)
  apply auto
  done

lemma sym_refs_upd_tcb_sD:
  "\<lbrakk> sym_refs ((state_refs_of' s) (p := {})); valid_pspace' s;
            ko_at' (tcb :: tcb) p s \<rbrakk>
      \<Longrightarrow> \<exists>s'. sym_refs (state_refs_of' s')
               \<and> (\<forall>p' (ko' :: endpoint).
                          ko_at' ko' p' s \<longrightarrow> ko_at' ko' p' s')
               \<and> (\<forall>p' (ko' :: async_endpoint).
                          ko_at' ko' p' s \<longrightarrow> ko_at' ko' p' s')
               \<and> (st_tcb_at' (op = Running) p s')"
  apply (drule(2) sym_refs_upd_sD[where koEx="makeObject\<lparr>tcbState := Running\<rparr>"])
    apply simp
   apply (simp add: objBits_simps)
  apply (erule exEI)
  apply clarsimp
  apply (auto simp: st_tcb_at'_def elim!: obj_at'_weakenE)
  done

lemma fastpath_enqueue_ccorres:
  "\<lbrakk> epptr' = ep_Ptr epptr \<rbrakk> \<Longrightarrow>
   ccorres dc xfdc
         (ko_at' ep epptr and (\<lambda>s. thread = ksCurThread s)
                and (\<lambda>s. sym_refs ((state_refs_of' s) (thread := {})))
                and K (\<not> isSendEP ep) and valid_pspace' and cur_tcb')
         UNIV hs
     (setEndpoint epptr (case ep of IdleEP \<Rightarrow> RecvEP [thread] | RecvEP ts \<Rightarrow> RecvEP (ts @ [thread])))
     (\<acute>ret__unsigned_long :== CALL endpoint_ptr_get_epQueue_tail(epptr');;
      \<acute>endpointTail :== tcb_Ptr \<acute>ret__unsigned_long;;
      IF \<acute>endpointTail = tcb_Ptr 0 THEN
         (Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t \<acute>ksCurThread\<rbrace>
            (ptr_basic_update (\<lambda>s. tcb_Ptr_Ptr &((ksCurThread_' (globals s))\<rightarrow>[''tcbEPPrev_C''])) (\<lambda>_. NULL)));;
         (Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t \<acute>ksCurThread\<rbrace>
          (ptr_basic_update (\<lambda>s. tcb_Ptr_Ptr &((ksCurThread_' (globals s))\<rightarrow>[''tcbEPNext_C''])) (\<lambda>_. NULL)));;
           (CALL endpoint_ptr_set_epQueue_head_np(epptr',ucast (ptr_val \<acute>ksCurThread)));;
           (CALL endpoint_ptr_mset_epQueue_tail_state(epptr',ucast (ptr_val \<acute>ksCurThread),
            scast EPState_Recv))
      ELSE
        Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t \<acute>endpointTail\<rbrace>
          (ptr_basic_update (\<lambda>s. tcb_Ptr_Ptr &((endpointTail_' s)\<rightarrow>[''tcbEPNext_C'']))
                      (ksCurThread_' o globals));;
         (Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t \<acute>ksCurThread\<rbrace>
          (ptr_basic_update (\<lambda>s. tcb_Ptr_Ptr &((ksCurThread_' (globals s))\<rightarrow>[''tcbEPPrev_C'']))
                      endpointTail_'));;
         (Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t \<acute>ksCurThread\<rbrace>
          (ptr_basic_update (\<lambda>s. tcb_Ptr_Ptr &((ksCurThread_' (globals s))\<rightarrow>[''tcbEPNext_C'']))
                      (\<lambda>_. NULL)));;
           (CALL endpoint_ptr_mset_epQueue_tail_state(epptr',ucast (ptr_val \<acute>ksCurThread),
            scast EPState_Recv))
      FI)"
  unfolding setEndpoint_def
  apply clarsimp
  apply (rule setObject_ccorres_helper[rotated])
    apply simp
   apply (simp add: objBits_simps)
  apply (rule conseqPre, vcg)
  apply clarsimp
  apply (drule(1) ko_at_obj_congD')
  apply (frule ko_at_valid_ep', clarsimp)
  apply (rule cmap_relationE1[OF cmap_relation_ep], assumption,
         erule ko_at_projectKO_opt)
  apply (simp add: cur_tcb'_def)
  apply (drule(1) obj_at_cslift_tcb)
  apply (clarsimp simp: typ_heap_simps' valid_ep'_def rf_sr_ksCurThread)
  apply (cases ep,
         simp_all add: isSendEP_def cendpoint_relation_def Let_def
                       tcb_queue_relation'_def)
   apply (rename_tac list)
   apply (clarsimp simp: NULL_ptr_val[symmetric] tcb_queue_relation_last_not_NULL
                         ct_in_state'_def
                  dest!: trans [OF sym [OF ptr_val_def] arg_cong[where f=ptr_val]])
   apply (frule obj_at_cslift_tcb[rotated], erule(1) bspec[OF _ last_in_set])
   apply clarsimp
   apply (drule(2) sym_refs_upd_tcb_sD)
   apply clarsimp
   apply (frule st_tcb_at_not_in_ep_queue,
          fastforce, simp+)
   apply (subgoal_tac "ksCurThread \<sigma> \<noteq> last list")
    prefer 2
    apply clarsimp
   apply (clarsimp simp: typ_heap_simps' EPState_Recv_def mask_def
                         is_aligned_weaken[OF is_aligned_tcb_ptr_to_ctcb_ptr])
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def)
   apply (rule conjI)
    apply (clarsimp simp: cpspace_relation_def update_ep_map_tos
                          typ_heap_simps')
    apply (rule conjI, erule ctcb_relation_null_queue_ptrs)
     apply (rule ext, simp add: tcb_null_queue_ptrs_def
                         split: split_if)
    apply (rule conjI)
     apply (rule_tac S="tcb_ptr_to_ctcb_ptr ` set (ksCurThread \<sigma> # list)"
                   in cpspace_relation_ep_update_an_ep,
                 assumption+)
         apply (simp add: cendpoint_relation_def Let_def EPState_Recv_def
                          tcb_queue_relation'_def)
         apply (drule_tac qend="tcb_ptr_to_ctcb_ptr (last list)"
                     and qend'="tcb_ptr_to_ctcb_ptr (ksCurThread \<sigma>)"
                     and tn_update="tcbEPNext_C_update"
                     and tp_update="tcbEPPrev_C_update"
                     in tcb_queue_relation_append,
                    clarsimp+, simp_all)[1]
           apply (rule sym, erule init_append_last)
          apply (fastforce simp: tcb_at_not_NULL)
         apply (clarsimp simp add: tcb_at_not_NULL[OF obj_at'_weakenE[OF _ TrueI]])
        apply clarsimp+
     apply (subst st_tcb_at_not_in_ep_queue, assumption, blast, clarsimp+)
     apply (drule(1) ep_ep_disjoint[rotated -1, where epptr=epptr],
            blast, blast,
            simp_all add: Int_commute endpoint_not_idle_cases image_image)[1]
    apply (erule iffD1 [OF cmap_relation_cong, OF refl refl, rotated -1])
    apply simp
    apply (rule casync_relation_double_fun_upd)
     apply (rule casync_endpoint_relation_ep_queue, assumption+)
        apply fastforce
       apply (simp add: isRecvEP_def)
      apply simp
     apply (fastforce dest!: map_to_ko_atI)
    apply (rule casync_endpoint_relation_q_cong)
    apply (clarsimp split: split_if)
    apply (clarsimp simp: restrict_map_def aep_q_refs_of'_def
                   split: split_if Structures_H.async_endpoint.split_asm)
    apply (erule notE[rotated], erule st_tcb_at_not_in_aep_queue,
           auto dest!: map_to_ko_atI)[1]
   apply (simp add: carch_state_relation_def typ_heap_simps'
                    cmachine_state_relation_def h_t_valid_clift_Some_iff)
   apply (erule cready_queues_relation_null_queue_ptrs)
   apply (rule ext, simp add: tcb_null_ep_ptrs_def split: split_if)
  apply (clarsimp simp: typ_heap_simps' EPState_Recv_def mask_def
                        is_aligned_weaken[OF is_aligned_tcb_ptr_to_ctcb_ptr])
  apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def)
  apply (drule(2) sym_refs_upd_tcb_sD)
  apply (rule conjI)
   apply (clarsimp simp: cpspace_relation_def update_ep_map_tos
                         typ_heap_simps' ct_in_state'_def)
   apply (rule conjI, erule ctcb_relation_null_queue_ptrs)
    apply (rule ext, simp add: tcb_null_queue_ptrs_def
                        split: split_if)
   apply (rule conjI)
    apply (rule_tac S="{tcb_ptr_to_ctcb_ptr (ksCurThread \<sigma>)}"
                 in cpspace_relation_ep_update_an_ep, assumption+)
        apply (simp add: cendpoint_relation_def Let_def EPState_Recv_def
                         tcb_queue_relation'_def)
       apply clarsimp+
    apply (erule notE[rotated], erule st_tcb_at_not_in_ep_queue,
           auto)[1]
   apply (erule iffD1 [OF cmap_relation_cong, OF refl refl, rotated -1])
   apply simp
   apply (rule casync_endpoint_relation_q_cong)
   apply (clarsimp split: split_if)
   apply (clarsimp simp: restrict_map_def aep_q_refs_of'_def
                  split: split_if Structures_H.async_endpoint.split_asm)
   apply (erule notE[rotated], rule st_tcb_at_not_in_aep_queue,
          assumption+, auto dest!: map_to_ko_atI)[1]
  apply (simp add: carch_state_relation_def typ_heap_simps'
                   cmachine_state_relation_def h_t_valid_clift_Some_iff)
  apply (erule cready_queues_relation_null_queue_ptrs)
  apply (rule ext, simp add: tcb_null_ep_ptrs_def split: split_if)
  done


lemma ccorres_updateCap [corres]:
  fixes ptr :: "cstate \<Rightarrow> cte_C ptr" and val :: "cstate \<Rightarrow> cap_C"
  shows "ccorres dc xfdc \<top>
        ({s. ccap_relation cap (val s)} \<inter> {s. ptr s = Ptr dest}) hs
        (updateCap dest cap)
        (Basic
  (\<lambda>s. globals_update
   (t_hrs_'_update
     (hrs_mem_update (heap_update (Ptr &(ptr s\<rightarrow>[''cap_C''])) (val s)))) s))"
  unfolding updateCap_def
  apply (cinitlift ptr)
  apply (erule ssubst)
  apply (rule ccorres_guard_imp2)
  apply (rule ccorres_pre_getCTE)
  apply (rule_tac P = "\<lambda>s. ctes_of s dest = Some rva" in ccorres_from_vcg [where P' = "{s. ccap_relation cap (val s)}"])
  apply (rule allI)
  apply (rule conseqPre)
  apply vcg
  apply clarsimp
  apply (rule fst_setCTE [OF ctes_of_cte_at], assumption)
   apply (erule bexI [rotated])
   apply (clarsimp simp: cte_wp_at_ctes_of)
   apply (frule (1) rf_sr_ctes_of_clift)
   apply (clarsimp simp add: rf_sr_def cstate_relation_def typ_heap_simps
     Let_def cpspace_relation_def)
   apply (rule conjI)
    apply (erule (3) cpspace_cte_relation_upd_capI)
   apply (erule_tac t = s' in ssubst)
   apply (simp add: heap_to_page_data_def)
   apply (rule conjI)
    apply (erule (1) setCTE_tcb_case)
   apply (simp add: carch_state_relation_def cmachine_state_relation_def
                    typ_heap_simps h_t_valid_clift_Some_iff)
  apply clarsimp
  done


lemma setCTE_rf_sr:
  "\<lbrakk> (\<sigma>, s) \<in> rf_sr; ctes_of \<sigma> ptr = Some cte'';
     cslift s' = ((cslift s)(cte_Ptr ptr \<mapsto> cte'));
     ccte_relation cte cte';
     types_proofs.cslift_all_but_cte_C s' s;
     hrs_htd (t_hrs_' (globals s')) = hrs_htd (t_hrs_' (globals s));
     (globals s')\<lparr> t_hrs_' := undefined \<rparr>
          = (globals s)\<lparr> t_hrs_' := undefined \<rparr> \<rbrakk>

      \<Longrightarrow>
   \<exists>x\<in>fst (setCTE ptr cte \<sigma>).
             (snd x, s') \<in> rf_sr"
  apply (rule fst_setCTE[OF ctes_of_cte_at], assumption)
  apply (erule rev_bexI)
  apply (subgoal_tac "\<exists>hrs. globals s' = globals s
                          \<lparr> t_hrs_' := hrs \<rparr>")
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                         typ_heap_simps' cpspace_relation_def)
   apply (rule conjI)
    apply (erule(2) cmap_relation_updI, simp)
   apply (erule_tac t = s'a in ssubst)
   apply (simp add: heap_to_page_data_def)
   apply (rule conjI)
    apply (erule(1) setCTE_tcb_case)
   apply (simp add: carch_state_relation_def cmachine_state_relation_def
                    typ_heap_simps' h_t_valid_clift_Some_iff)
  apply (cases "globals s", cases "globals s'")
  apply simp
  done

lemma getCTE_setCTE_rf_sr:
  "\<lbrakk> (\<sigma>, s) \<in> rf_sr; ctes_of \<sigma> ptr = Some cte;
     cslift s' = ((cslift s)(cte_Ptr ptr \<mapsto> cte'));
     ccte_relation (f cte) cte';
     types_proofs.cslift_all_but_cte_C s' s;
     hrs_htd (t_hrs_' (globals s')) = hrs_htd (t_hrs_' (globals s));
     (globals s')\<lparr> t_hrs_' := undefined \<rparr>
          = (globals s)\<lparr> t_hrs_' := undefined \<rparr> \<rbrakk>

      \<Longrightarrow>
   \<exists>x\<in>fst ((do cte \<leftarrow> getCTE ptr;
                      setCTE ptr (f cte)
                    od)
                    \<sigma>).
             (snd x, s') \<in> rf_sr"
  apply (drule setCTE_rf_sr, assumption+)
  apply (clarsimp simp: Bex_def in_bind_split in_getCTE2 cte_wp_at_ctes_of)
  done

lemma ccte_relation_eq_ccap_relation:
  notes option.case_cong_weak [cong]
  shows
  "ccte_relation cte ccte
      = (ccap_relation (cteCap cte) (cte_C.cap_C ccte)
            \<and> mdb_node_to_H (mdb_node_lift (cteMDBNode_C ccte))
                   = (cteMDBNode cte))"
  apply (simp add: ccte_relation_def option_map_Some_eq2 cte_lift_def
                   ccap_relation_def)
  apply (simp add: cte_to_H_def split: option.split)
  apply (cases cte, clarsimp simp: c_valid_cte_def conj_comms)
  done

lemma cap_reply_cap_ptr_new_np_updateCap_ccorres:
  "ccorres dc xfdc
        (cte_at' ptr and tcb_at' thread)
        (UNIV \<inter> {s. cap_ptr_' s = cap_Ptr &(cte_Ptr ptr \<rightarrow> [''cap_C''])}
              \<inter> {s. capTCBPtr_' s = ptr_val (tcb_ptr_to_ctcb_ptr thread)}
              \<inter> {s. capReplyMaster_' s = from_bool m}) []
     (updateCap ptr (ReplyCap thread m))
     (Call cap_reply_cap_ptr_new_np_'proc)"
  apply (rule ccorres_from_vcg, rule allI)
  apply (rule conseqPre, vcg)
  apply (clarsimp simp: cte_wp_at_ctes_of word_sle_def)
   apply (rule cmap_relationE1[OF cmap_relation_cte], assumption+)
  apply (clarsimp simp: updateCap_def split_def typ_heap_simps'
                        word_sless_def word_sle_def)
  apply (erule(1) getCTE_setCTE_rf_sr, simp_all add: typ_heap_simps')
  apply (clarsimp simp: ccte_relation_eq_ccap_relation
                        ccap_relation_def c_valid_cap_def)
  apply (frule is_aligned_tcb_ptr_to_ctcb_ptr)
  apply (rule ssubst[OF cap_lift_reply_cap])
   apply (simp add: cap_get_tag_def cap_reply_cap_def
                    mask_def word_ao_dist
                    limited_and_simps
                    limited_and_simps1[OF lshift_limited_and, OF limited_and_from_bool])
  apply (simp add: cap_to_H_simps word_ao_dist cl_valid_cap_def
                   limited_and_simps cap_reply_cap_def
                   limited_and_simps1[OF lshift_limited_and, OF limited_and_from_bool]
                   shiftr_over_or_dist word_bw_assocs)
  done

lemma fastpath_copy_mrs_ccorres:
notes min_simps [simp del]
shows
  "ccorres dc xfdc (\<top> and (\<lambda>_. ln <= length State_H.msgRegisters))
     (UNIV \<inter> {s. unat (length_' s) = ln}
           \<inter> {s. src_' s = tcb_ptr_to_ctcb_ptr src}
           \<inter> {s. dest_' s = tcb_ptr_to_ctcb_ptr dest}) []
     (forM_x (take ln State_H.msgRegisters)
             (\<lambda>r. do v \<leftarrow> asUser src (getRegister r);
                    asUser dest (setRegister r v) od))
     (Call fastpath_copy_mrs_'proc)"
  apply (rule ccorres_gen_asm)
  apply (cinit' lift: length_' src_' dest_' simp: word_sle_def word_sless_def)
   apply (unfold whileAnno_def)
   apply (rule ccorres_rel_imp)
    apply (rule_tac F="K \<top>" in ccorres_mapM_x_while)
        apply clarsimp
        apply (rule ccorres_guard_imp2)
         apply (rule ccorres_rhs_assoc)+
         apply (rule_tac xf'="i_'" in ccorres_abstract, ceqv)
         apply (rule ccorres_Guard_Seq)+
         apply csymbr
         apply (ctac(no_vcg))
          apply ctac
         apply wp
        apply (clarsimp simp: rf_sr_ksCurThread)
        apply (simp add: msgRegisters_ccorres[symmetric] length_msgRegisters)
        apply (simp add: n_msgRegisters_def msgRegisters_unfold)
        apply (drule(1) order_less_le_trans)
        apply (clarsimp simp: "StrictC'_register_defs" msgRegisters_def fupdate_def
          | drule nat_less_cases' | erule disjE)+
       apply (simp add: min.absorb2)
      apply (rule allI, rule conseqPre, vcg)
      apply (simp)
     apply (simp add: length_msgRegisters n_msgRegisters_def
       word_bits_def hoare_TrueI)+
  done

lemma switchToThread_ksCurThread:
  "\<lbrace>\<lambda>s. P t\<rbrace> switchToThread t \<lbrace>\<lambda>rv s. P (ksCurThread s)\<rbrace>"
  apply (simp add: switchToThread_def setCurThread_def)
  apply (wp | simp)+
  done

lemma updateCap_cte_wp_at_cteMDBNode:
  "\<lbrace>cte_wp_at' (\<lambda>cte. P (cteMDBNode cte)) p\<rbrace>
     updateCap ptr cap
   \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>cte. P (cteMDBNode cte)) p\<rbrace>"
  apply (wp updateCap_cte_wp_at_cases)
  apply (simp add: o_def)
  done

lemma ctes_of_Some_cte_wp_at:
  "ctes_of s p = Some cte \<Longrightarrow> cte_wp_at' P p s = P cte"
  by (clarsimp simp: cte_wp_at_ctes_of)

lemma user_getreg_wp:
  "\<lbrace>\<lambda>s. tcb_at' t s \<and> (\<forall>rv. obj_at' (\<lambda>tcb. tcbContext tcb r = rv) t s \<longrightarrow> Q rv s)\<rbrace>
      asUser t (getRegister r) \<lbrace>Q\<rbrace>"
  apply (rule_tac Q="\<lambda>rv s. \<exists>rv'. rv' = rv \<and> Q rv' s" in hoare_post_imp)
   apply simp
  apply (rule hoare_pre, wp hoare_vcg_ex_lift user_getreg_rv)
  apply (clarsimp simp: obj_at'_def)
  done

lemma cap_page_directory_cap_get_capPDBasePtr_spec2:
  "\<forall>s. \<Gamma>\<turnstile> \<lbrace>s. True\<rbrace>
     Call cap_page_directory_cap_get_capPDBasePtr_'proc
   \<lbrace>cap_get_tag \<^bsup>s\<^esup>cap = scast cap_page_directory_cap
       \<longrightarrow> \<acute>ret__unsigned_long = capPDBasePtr_CL (cap_page_directory_cap_lift \<^bsup>s\<^esup>cap)\<rbrace>"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply vcg
  apply (clarsimp simp: word_sle_def word_sless_def
                        cap_page_directory_cap_lift_def
                        cap_lift_page_directory_cap)
  done

lemma setUntypedCapAsFull_replyCap[simp]:
  "setUntypedCapAsFull cap (ReplyCap curThread False) slot =  return ()"
   by (clarsimp simp:setUntypedCapAsFull_def isCap_simps)

lemma fastpath_call_ccorres:
  notes hoare_TrueI[simp]
  shows "ccorres dc xfdc
     (\<lambda>s. invs' s \<and> ct_in_state' (op = Running) s
                  \<and> obj_at' (\<lambda>tcb. tcbContext tcb State_H.capRegister = cptr
                                 \<and> tcbContext tcb State_H.msgInfoRegister = msginfo)
                        (ksCurThread s) s)
     (UNIV \<inter> {s. cptr_' s = cptr} \<inter> {s. msgInfo_' s = msginfo}) []
     (fastpaths SysCall) (Call fastpath_call_'proc)"
  proof -
   have [simp]: "scast Kernel_C.tcbCaller = tcbCallerSlot"
     by (simp add:Kernel_C.tcbCaller_def tcbCallerSlot_def)
   have [simp]: "scast Kernel_C.tcbVTable = tcbVTableSlot"
     by (simp add:Kernel_C.tcbVTable_def tcbVTableSlot_def)

  have tcbs_of_cte_wp_at_vtable:
    "\<And>s tcb ptr. tcbs_of s ptr = Some tcb \<Longrightarrow>
    cte_wp_at' \<top> (ptr + 0x10 * tcbVTableSlot) s"
    apply (clarsimp simp:tcbs_of_def cte_at'_obj_at'
      split:if_splits)
    apply (drule_tac x = "0x10 * tcbVTableSlot" in bspec)
     apply (simp add:tcb_cte_cases_def tcbVTableSlot_def)
    apply simp
    done

  have tcbs_of_cte_wp_at_caller:
    "\<And>s tcb ptr. tcbs_of s ptr = Some tcb \<Longrightarrow>
    cte_wp_at' \<top> (ptr + 0x10 * tcbCallerSlot) s"
    apply (clarsimp simp:tcbs_of_def cte_at'_obj_at'
      split:if_splits)
    apply (drule_tac x = "0x10 * tcbCallerSlot" in bspec)
     apply (simp add:tcb_cte_cases_def tcbCallerSlot_def)
    apply simp
    done

  have tcbs_of_aligned':
    "\<And>s ptr tcb. \<lbrakk>tcbs_of s ptr = Some tcb;pspace_aligned' s\<rbrakk> \<Longrightarrow> is_aligned ptr 9"
    apply (clarsimp simp:tcbs_of_def obj_at'_def split:if_splits)
    apply (drule pspace_alignedD')
    apply simp+
    apply (simp add:projectKO_opt_tcb objBitsKO_def
      split: Structures_H.kernel_object.splits)
    done
  show ?thesis
  using [[goals_limit = 1]]
  apply (cinit lift: cptr_' msgInfo_')
   apply (simp add: catch_liftE_bindE unlessE_throw_catch_If
                    unifyFailure_catch_If catch_liftE
                    getMessageInfo_def alternative_bind
              cong: if_cong call_ignore_cong del: Collect_const)
   apply (rule ccorres_pre_getCurThread)
   apply (rename_tac curThread)
   apply (rule ccorres_symb_exec_l3[OF _ user_getreg_inv' _ empty_fail_user_getreg])+
     apply (rename_tac msginfo' cptr')
     apply (rule_tac P="msginfo' = msginfo \<and> cptr' = cptr" in ccorres_gen_asm)
     apply (simp del: Collect_const cong: call_ignore_cong)
     apply (simp only: )
     apply (csymbr, csymbr)
     apply (rule_tac r'="\<lambda>ft ft'. (ft' = scast fault_null_fault) = (ft = None)"
               and xf'="fault_type_'" in ccorres_split_nothrow)
         apply (rule_tac P="cur_tcb' and (\<lambda>s. curThread = ksCurThread s)"
                   in ccorres_from_vcg[where P'=UNIV])
         apply (rule allI, rule conseqPre, vcg)
         apply (clarsimp simp: cur_tcb'_def rf_sr_ksCurThread)
         apply (drule(1) obj_at_cslift_tcb, clarsimp)
         apply (clarsimp simp: typ_heap_simps' ctcb_relation_def cfault_rel_def)
         apply (rule rev_bexI, erule threadGet_eq)
         apply (clarsimp simp: fault_lift_def Let_def split: split_if_asm)
        apply ceqv
       apply csymbr
       apply (simp del: Collect_const cong: call_ignore_cong)
       apply (rule ccorres_Cond_rhs_Seq)
        apply (rule ccorres_alternative2)
        apply (rule ccorres_split_throws)
         apply (fold dc_def)[1]
         apply (rule ccorres_call_hSkip)
           apply (rule slowpath_ccorres)
          apply simp
         apply simp
        apply (vcg exspec=slowpath_noreturn_spec)
       apply (rule ccorres_alternative1)
       apply (rule ccorres_if_lhs[rotated])
        apply (rule ccorres_inst[where P=\<top> and P'=UNIV])
        apply simp
       apply (simp del: Collect_const cong: call_ignore_cong)
       apply (elim conjE)
       apply (simp add: getThreadCSpaceRoot_def locateSlot_conv
                   del: Collect_const cong: call_ignore_cong)
       apply (rule ccorres_pre_getCTE2)
       apply (rule ccorres_Guard_Seq)
       apply (simp only: )
       apply (ctac add: lookup_fp_ccorres)
         apply (rename_tac luRet ep_cap)
         apply (csymbr, csymbr)
         apply (simp add: ccap_relation_case_sum_Null_endpoint
                          of_bl_from_bool from_bool_0
                     del: Collect_const cong: call_ignore_cong)
         apply (rule ccorres_Cond_rhs_Seq)
          apply (simp add: from_bool_0 if_1_0_0 cong: if_cong)
          apply (rule ccorres_cond_true_seq)
          apply (rule ccorres_split_throws)
           apply (fold dc_def)[1]
           apply (rule ccorres_call_hSkip)
             apply (rule slowpath_ccorres, simp+)
          apply (vcg exspec=slowpath_noreturn_spec)
         apply (rule ccorres_rhs_assoc)+
         apply csymbr+
         apply (simp add: if_1_0_0 isRight_case_sum
                     del: Collect_const cong: call_ignore_cong)
         apply (elim conjE)
         apply (frule(1) cap_get_tag_isCap[THEN iffD2])
         apply (simp add: ccap_relation_ep_helpers from_bool_0
                     del: Collect_const cong: call_ignore_cong)
         apply (rule ccorres_Cond_rhs_Seq)
          apply simp
          apply (rule ccorres_split_throws)
           apply (fold dc_def)[1]
           apply (rule ccorres_call_hSkip)
             apply (rule slowpath_ccorres, simp+)
          apply (vcg exspec=slowpath_noreturn_spec)
         apply (simp del: Collect_const cong: call_ignore_cong)
         apply (csymbr, csymbr)
         apply (simp add: ccap_relation_ep_helpers
                     del: Collect_const cong: call_ignore_cong)
         apply (rule ccorres_rhs_assoc2, rule ccorres_rhs_assoc2)
         apply (rule_tac xf'="\<lambda>s. (dest_' s, ret__unsigned_long_' s)"
                      and r'="\<lambda>ep v. snd v = scast EPState_Recv = isRecvEP ep
                               \<and> (isRecvEP ep \<longrightarrow> epQueue ep \<noteq> []
                                          \<and> fst v = tcb_ptr_to_ctcb_ptr (hd (epQueue ep)))"
                     in ccorres_split_nothrow)
             apply (rule ccorres_add_return2)
             apply (rule ccorres_pre_getEndpoint, rename_tac ep)
             apply (rule_tac P="ko_at' ep (capEPPtr (theRight luRet)) and valid_objs'"
                          in ccorres_from_vcg[where P'=UNIV])
             apply (rule allI, rule conseqPre, vcg)
             apply (clarsimp simp: return_def)
             apply (erule cmap_relationE1[OF cmap_relation_ep], erule ko_at_projectKO_opt)
             apply (frule(1) ko_at_valid_ep')
             apply (clarsimp simp: typ_heap_simps')
             apply (simp add: cendpoint_relation_def Let_def isRecvEP_def
                              endpoint_state_defs valid_ep'_def
                       split: endpoint.split_asm)
             apply (clarsimp simp: tcb_queue_relation'_def neq_Nil_conv)
            apply (rule ceqv_tuple2)
             apply ceqv
            apply ceqv
           apply (rename_tac send_ep send_ep_c)
           apply (rule_tac P="ko_at' send_ep (capEPPtr (theRight luRet))
                                and valid_objs'" in ccorres_cross_over_guard)
           apply (simp del: Collect_const cong: call_ignore_cong)
           apply (rule ccorres_Cond_rhs_Seq)
            apply simp
            apply (rule ccorres_split_throws)
             apply (fold dc_def)[1]
             apply (rule ccorres_call_hSkip)
               apply (rule slowpath_ccorres, simp+)
            apply (vcg exspec=slowpath_noreturn_spec)
           apply (simp add: getThreadVSpaceRoot_def locateSlot_conv
                       del: Collect_const cong: call_ignore_cong)
           apply (rule ccorres_move_c_guard_cte)
           apply (rule ccorres_move_const_guard)+
           apply (rule_tac var="newVTable_'" and var_update="newVTable_'_update"
                        in getCTE_h_val_ccorres_split[where P=\<top>])
             apply simp
            apply ceqv
           apply (rename_tac pd_cap pd_cap_c)
           apply (rule ccorres_symb_exec_r)
             apply (rule_tac xf'=ret__unsigned_long_' in ccorres_abstract, ceqv)
             apply (rename_tac pd_cap_c_ptr_maybe)
             apply csymbr+
             apply (simp add: isValidVTableRoot_conv from_bool_0
                         del: Collect_const cong: call_ignore_cong)
             apply (rule ccorres_Cond_rhs_Seq)
              apply simp
              apply (rule ccorres_split_throws)
               apply (fold dc_def)[1]
               apply (rule ccorres_call_hSkip)
                 apply (rule slowpath_ccorres, simp+)
              apply (vcg exspec=slowpath_noreturn_spec)
             apply (simp del: Collect_const cong: call_ignore_cong)
             apply (drule isValidVTableRootD)
             apply (rule_tac P="pd_cap_c_ptr_maybe = capUntypedPtr (cteCap pd_cap)"
                         in ccorres_gen_asm2)
             apply (simp add: ccap_relation_pd_helper cong: call_ignore_cong)
             apply (rule stored_hw_asid_get_ccorres_split[where P=\<top>], ceqv)
             apply (rule ccorres_move_c_guard_tcb ccorres_Guard_Seq)+
             apply (rule ccorres_symb_exec_l3[OF _ threadGet_inv _ empty_fail_threadGet])
              apply (rule ccorres_symb_exec_l3[OF _ threadGet_inv _ empty_fail_threadGet])
               apply (rename_tac curPrio destPrio)
               apply (rule ccorres_seq_cond_raise[THEN iffD2])
               apply (rule_tac R="obj_at' (op = curPrio \<circ> tcbPriority) curThread
                                   and obj_at' (op = destPrio \<circ> tcbPriority)
                                             (hd (epQueue send_ep))
                                   and (\<lambda>s. ksCurThread s = curThread)"
                              in ccorres_cond2')
                 apply clarsimp
                 apply (drule(1) obj_at_cslift_tcb)+
                 apply (clarsimp simp: typ_heap_simps' rf_sr_ksCurThread)
                 apply (simp add: ctcb_relation_unat_tcbPriority_C
                                  word_less_nat_alt linorder_not_le)
                apply simp
                apply (rule ccorres_split_throws)
                 apply (fold dc_def)[1]
                 apply (rule ccorres_call_hSkip)
                   apply (rule slowpath_ccorres, simp+)
                apply (vcg exspec=slowpath_noreturn_spec)
               apply (simp del: Collect_const cong: call_ignore_cong)
               apply csymbr+
               apply (simp add: if_1_0_0 ccap_relation_ep_helpers from_bool_0
                           del: Collect_const cong: call_ignore_cong)
               apply (rule ccorres_Cond_rhs_Seq)
                apply simp
                apply (rule ccorres_cond_true_seq)
                apply (rule ccorres_split_throws)
                 apply (fold dc_def)[1]
                 apply (rule ccorres_call_hSkip)
                   apply (rule slowpath_ccorres, simp+)
                apply (vcg exspec=slowpath_noreturn_spec)
               apply (simp del: Collect_const cong: call_ignore_cong)
               apply (rule ccorres_rhs_assoc)+
               apply (rule_tac xf'="ret__unsigned_long_'"
                            and r'="\<lambda>rv rv'. rv' = from_bool (blockingIPCDiminishCaps rv)"
                             in ccorres_split_nothrow)
                   apply (rule_tac P="ko_at' send_ep (capEPPtr (theRight luRet))
                                       and (sym_refs o state_refs_of')"
                            in ccorres_from_vcg[where P'=UNIV])
                   apply (rule allI, rule conseqPre, vcg)
                   apply (clarsimp simp: isRecvEP_endpoint_case
                                         neq_Nil_conv)
                   apply (drule(1) sym_refs_ko_atD')
                   apply (clarsimp simp: typ_heap_simps' ep_q_refs_of'_def
                                         isRecvEP_endpoint_case
                                         st_tcb_at_refs_of_rev'
                                         st_tcb_at'_def)
                   apply (drule(1) obj_at_cslift_tcb)
                   apply (clarsimp simp: typ_heap_simps' getThreadState_def)
                   apply (rule rev_bexI, erule threadGet_eq)
                   apply (clarsimp simp: ctcb_relation_def isBlockedOnReceive_def
                                         cthread_state_relation_def)
                   apply (simp add: thread_state_lift_def word_size)
                  apply ceqv
                 apply (rename_tac send_state send_state_c)
                 apply csymbr
                 apply (simp add: if_1_0_0 ccap_relation_ep_helpers from_bool_0
                             del: Collect_const cong: call_ignore_cong)
                 apply (rule ccorres_Cond_rhs_Seq)
                  apply simp
                  apply (rule ccorres_split_throws)
                   apply (fold dc_def)[1]
                   apply (rule ccorres_call_hSkip)
                     apply (rule slowpath_ccorres, simp+)
                  apply (vcg exspec=slowpath_noreturn_spec)
                 apply (simp add: ccap_relation_pd_helper cap_get_tag_isCap_ArchObject2
                         del: Collect_const WordSetup.ptr_add_def cong: call_ignore_cong)
                 apply csymbr
                 apply (rule ccorres_symb_exec_l3[OF _ gets_inv _ empty_fail_gets])
                  apply (rename_tac asidMap)
                  apply (rule_tac P="asid_map_pd_to_hwasids asidMap (capPDBasePtr (capCap ((cteCap pd_cap))))
                                        = set_option (pde_stored_asid shw_asid)" in ccorres_gen_asm)
                  apply (simp del: Collect_const cong: call_ignore_cong)
                  apply (rule ccorres_Cond_rhs_Seq)
                   apply (simp add: pde_stored_asid_def asid_map_pd_to_hwasids_def)
                   apply (rule ccorres_split_throws)
                    apply (fold dc_def)[1]
                    apply (rule ccorres_call_hSkip)
                      apply (rule slowpath_ccorres, simp+)
                   apply (vcg exspec=slowpath_noreturn_spec)
                  apply (simp add: pde_stored_asid_def asid_map_pd_to_hwasids_def
                                   to_bool_def
                              del: Collect_const cong: call_ignore_cong)

                  apply (rule ccorres_move_c_guard_tcb ccorres_Guard_Seq)+
                  apply (rule ccorres_symb_exec_l3[OF _ curDomain_inv _])
                    prefer 3
                    apply (simp only: curDomain_def, rule empty_fail_gets)
                   apply (rule ccorres_symb_exec_l3[OF _ threadGet_inv _ empty_fail_threadGet])
                    apply (rename_tac curDom destDom)

                    apply (rule ccorres_seq_cond_raise[THEN iffD2])
                    apply (rule_tac R="obj_at' (op = destDom \<circ> tcbDomain)
                                                  (hd (epQueue send_ep))
                                        and (\<lambda>s. ksCurDomain s = curDom)"
                                   in ccorres_cond2')
                      apply clarsimp
                      apply (drule(1) obj_at_cslift_tcb)+
                      apply (clarsimp simp: typ_heap_simps' rf_sr_ksCurDomain)
                      apply (drule ctcb_relation_tcbDomain[symmetric])
                      apply (clarsimp simp: up_ucast_inj_eq[symmetric] maxDom_def)
                     apply simp
                     apply (rule ccorres_split_throws)
                      apply (fold dc_def)[1]
                      apply (rule ccorres_call_hSkip)
                        apply (rule slowpath_ccorres, simp+)
                     apply (vcg exspec=slowpath_noreturn_spec)
                    apply (simp del: Collect_const cong: call_ignore_cong)

                    apply (rule ccorres_rhs_assoc2)
                    apply (rule_tac xf'=xfdc and r'=dc in ccorres_split_nothrow)
                        apply (simp only: ucast_id tl_drop_1 One_nat_def)
                        apply (rule fastpath_dequeue_ccorres)
                        apply simp
                       apply ceqv
                      apply csymbr
                      apply (rule_tac xf'=xfdc and r'=dc in ccorres_split_nothrow)
                          apply (rule_tac P="cur_tcb' and (\<lambda>s. ksCurThread s = curThread)"
                                       in ccorres_from_vcg[where P'=UNIV])
                          apply (rule allI, rule conseqPre, vcg)
                          apply (clarsimp simp: cur_tcb'_def rf_sr_ksCurThread)
                          apply (drule(1) obj_at_cslift_tcb)
                          apply (clarsimp simp: typ_heap_simps')
                          apply (rule rev_bexI, erule threadSet_eq)
                          apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def)
                          apply (rule conjI)
                           apply (clarsimp simp: cpspace_relation_def typ_heap_simps'
                                                 update_tcb_map_tos map_to_tcbs_upd)
                           apply (subst map_to_ctes_upd_tcb_no_ctes, assumption)
                            apply (rule ball_tcb_cte_casesI, simp_all)[1]
                           apply (simp add: cep_relations_drop_fun_upd)
                           apply (erule cmap_relation_updI, erule ko_at_projectKO_opt)
                            apply (simp add: ctcb_relation_def cthread_state_relation_def)
                           apply simp
                          apply (rule conjI, erule cready_queues_relation_not_queue_ptrs)
                            apply (rule ext, simp split: split_if)
                           apply (rule ext, simp split: split_if)
                          apply (simp add: carch_state_relation_def cmachine_state_relation_def
                                           h_t_valid_clift_Some_iff)
                         apply ceqv
                        apply (rule ccorres_Guard_Seq)+
                        apply (simp add: getThreadReplySlot_def getThreadCallerSlot_def
                                         locateSlot_conv
                                    del: Collect_const cong: call_ignore_cong)
                        apply (rule ccorres_symb_exec_r)
                          apply (rule_tac xf'="replySlot_'" in ccorres_abstract, ceqv)
                          apply (rename_tac replySlot,
                                 rule_tac P="replySlot = cte_Ptr (curThread
                                               + (tcbReplySlot << cte_level_bits))"
                                    in ccorres_gen_asm2)
                          apply (rule ccorres_Guard_Seq)+
                          apply csymbr
                          apply (simp add: cteInsert_def bind_assoc dc_def[symmetric]
                                      del: Collect_const cong: call_ignore_cong)
                          apply (rule ccorres_pre_getCTE2 ccorres_assert2)+
                          apply (rename_tac curThreadReplyCTE curThreadReplyCTE2
                                            destCallerCTE)
                          apply (rule_tac P="curThreadReplyCTE2 = curThreadReplyCTE"
                                          in ccorres_gen_asm)
                          apply (rule ccorres_move_c_guard_cte)
                          apply (ctac add: cap_reply_cap_ptr_new_np_updateCap_ccorres)
                            apply (rule_tac xf'=xfdc and r'=dc in ccorres_split_nothrow)
                                apply (rule_tac P="cte_wp_at' (\<lambda>cte. cteMDBNode cte = nullMDBNode)
                                                     (hd (epQueue send_ep)
                                                           + (tcbCallerSlot << cte_level_bits))
                                               and cte_wp_at' (op = curThreadReplyCTE) (curThread
                                                           + (tcbReplySlot << cte_level_bits))
                                               and tcb_at' curThread and (no_0 o ctes_of)
                                               and tcb_at' (hd (epQueue send_ep))"
                                             in ccorres_from_vcg[where P'=UNIV])
                                apply (rule allI, rule conseqPre, vcg)
                                apply (clarsimp simp: cte_wp_at_ctes_of size_of_def
                                                      tcb_cnode_index_defs tcbCallerSlot_def
                                                      tcbReplySlot_def cte_level_bits_def
                                                      valid_mdb'_def valid_mdb_ctes_def)
                                apply (subst aligned_add_aligned, erule tcb_aligned',
                                       simp add: is_aligned_def, simp add: word_bits_def, simp)
                                apply (rule_tac x="hd (epQueue send_ep) + v" for v
                                          in cmap_relationE1[OF cmap_relation_cte], assumption+)
                                apply (clarsimp simp: typ_heap_simps' updateMDB_def Let_def)
                                apply (subst if_not_P)
                                 apply clarsimp
                                apply (simp add: split_def)
                                apply (rule getCTE_setCTE_rf_sr, simp_all)[1]
                                apply (case_tac destCallerCTE, case_tac curThreadReplyCTE,
                                       case_tac "cteMDBNode curThreadReplyCTE")
                                apply (clarsimp simp add: ccte_relation_eq_ccap_relation)
                                apply (clarsimp simp: nullMDBNode_def)
                               apply ceqv
                              apply (rule ccorres_move_c_guard_cte)
                              apply (rule_tac xf'=xfdc and r'=dc in ccorres_split_nothrow)
                                  apply (rule_tac P="cte_at' (hd (epQueue send_ep)
                                                               + (tcbCallerSlot << cte_level_bits))
                                                     and cte_wp_at' (op = curThreadReplyCTE) (curThread
                                                               + (tcbReplySlot << cte_level_bits))
                                                     and tcb_at' (hd (epQueue send_ep))
                                                     and (no_0 o ctes_of)"
                                                 in ccorres_from_vcg[where P'=UNIV])
                                  apply (rule allI, rule conseqPre, vcg)
                                  apply (clarsimp simp: cte_wp_at_ctes_of size_of_def
                                                        tcb_cnode_index_defs tcbCallerSlot_def
                                                        tcbReplySlot_def cte_level_bits_def)
                                  apply (subst aligned_add_aligned, erule tcb_aligned',
                                         simp add: is_aligned_def, simp add: word_bits_def, simp)
                                  apply (rule_tac x="curThread + 0x20" in cmap_relationE1[OF cmap_relation_cte],
                                         assumption+)
                                  apply (clarsimp simp: typ_heap_simps' updateMDB_def Let_def)
                                  apply (subst if_not_P)
                                   apply clarsimp
                                  apply (simp add: split_def)
                                  apply (rule getCTE_setCTE_rf_sr, simp_all)[1]
                                  apply (simp add: ccte_relation_eq_ccap_relation)
                                  apply (case_tac curThreadReplyCTE,
                                         case_tac "cteMDBNode curThreadReplyCTE",
                                         simp)
                                 apply ceqv
                                apply (simp add: updateMDB_def
                                  del: Collect_const cong: call_ignore_cong)
                                apply (rule ccorres_split_nothrow_dc)
                                   apply simp
                                   apply (ctac add: fastpath_copy_mrs_ccorres[unfolded forM_x_def])
                                  apply (rule ccorres_move_c_guard_tcb)
                                  apply (rule_tac r'=dc and xf'=xfdc in ccorres_split_nothrow)
                                      apply (simp add: setThreadState_runnable_simp)
                                      apply (rule_tac P=\<top> in threadSet_ccorres_lemma2, vcg)
                                      apply (clarsimp simp: typ_heap_simps' rf_sr_def
                                                            cstate_relation_def Let_def)
                                      apply (rule conjI)
                                       apply (clarsimp simp: cpspace_relation_def typ_heap_simps'
                                                             update_tcb_map_tos map_to_tcbs_upd)
                                       apply (subst map_to_ctes_upd_tcb_no_ctes, assumption)
                                        apply (rule ball_tcb_cte_casesI, simp_all)[1]
                                       apply (simp add: cep_relations_drop_fun_upd)
                                       apply (erule cmap_relation_updI, erule ko_at_projectKO_opt)
                                        apply (simp add: ctcb_relation_def cthread_state_relation_def)
                                       apply simp
                                      apply (rule conjI, erule cready_queues_relation_not_queue_ptrs)
                                        apply (rule ext, simp split: split_if)
                                       apply (rule ext, simp split: split_if)
                                      apply (simp add: carch_state_relation_def cmachine_state_relation_def
                                                       h_t_valid_clift_Some_iff)
                                     apply ceqv
                                    apply (simp only: bind_assoc[symmetric])
                                    apply (rule ccorres_split_nothrow_novcg_dc)
                                       apply simp
                                       apply (rule ccorres_call,
                                              rule_tac v=shw_asid and pd="capUntypedPtr (cteCap pd_cap)"
                                                    in switchToThread_fp_ccorres,
                                              simp+)[1]
                                      apply (rule_tac P="\<lambda>s. ksCurThread s = hd (epQueue send_ep)"
                                                   in ccorres_cross_over_guard)
                                      apply csymbr
                                      apply csymbr
                                      apply (rule ccorres_call_hSkip)
                                        apply (fold dc_def)[1]
                                        apply (rule fastpath_restore_ccorres)
                                       apply simp
                                      apply simp
                                     apply (simp add: setCurThread_def)
                                     apply wp
                                     apply (rule_tac P=\<top> in hoare_triv, simp)
                                    apply (simp add: imp_conjL rf_sr_ksCurThread del: all_imp_to_ex)
                                    apply (clarsimp simp: ccap_relation_ep_helpers guard_is_UNIV_def
                                                          mi_from_H_def)
                                   apply (simp add: pd_has_hwasid_def)
                                   apply (wp sts_ct_in_state_neq' sts_valid_objs')
                                  apply (simp del: Collect_const)
                                  apply (vcg exspec=thread_state_ptr_set_tsType_np_modifies)
                                 apply (simp add: pred_conj_def)
                                 apply (rule mapM_x_wp'[OF hoare_weaken_pre])
                                  apply wp
                                 apply clarsimp
                                apply simp
                                apply (vcg exspec=fastpath_copy_mrs_modifies)
                               apply (simp add: valid_tcb_state'_def)
                               apply wp
                               apply (wp updateMDB_weak_cte_wp_at)
                              apply simp
                              apply (vcg exspec=mdb_node_ptr_mset_mdbNext_mdbRevocable_mdbFirstBadged_modifies)
                             apply (simp add: o_def)
                             apply (wp | simp
                                        | wp_once updateMDB_weak_cte_wp_at
                                        | wp_once updateMDB_cte_wp_at_other)+
                            apply (vcg exspec=mdb_node_ptr_set_mdbPrev_np_modifies)
                           apply (wp updateCap_cte_wp_at_cteMDBNode
                                     updateCap_cte_wp_at_cases
                                     updateCap_no_0 | simp)+
                          apply (vcg exspec=cap_reply_cap_ptr_new_np_modifies)
                         apply (simp add: word_sle_def)
                         apply vcg
                        apply (rule conseqPre, vcg, clarsimp)
                       apply (simp add: cte_level_bits_def field_simps shiftl_t2n
                                        ctes_of_Some_cte_wp_at
                                   del: all_imp_to_ex)
                       apply (wp hoare_vcg_all_lift threadSet_ctes_of
                                 hoare_vcg_imp_lift threadSet_valid_objs'
                                 threadSet_st_tcb_at_state threadSet_cte_wp_at'
                               | simp)+
                      apply (vcg exspec=thread_state_ptr_set_tsType_np_modifies)
                     apply (simp only: imp_conv_disj[symmetric])
                     apply simp
                     apply (simp add: valid_tcb'_def tcb_cte_cases_def
                                      valid_tcb_state'_def)
                     apply (wp hoare_vcg_all_lift hoare_vcg_imp_lift
                               set_ep_valid_objs'
                               setObject_no_0_obj'[where 'a=endpoint, folded setEndpoint_def])
                    apply (simp del: Collect_const)
                    apply (vcg exspec=endpoint_ptr_mset_epQueue_tail_state_modifies
                             exspec=endpoint_ptr_set_epQueue_head_np_modifies)

                   apply simp
                   apply (rule threadGet_wp)
                  apply simp
                  apply wp[1]

                 apply simp
                 apply wp[1]
                apply simp
                apply (rule gts_wp')
               apply (simp del: Collect_const)
               apply (vcg exspec=thread_state_ptr_get_blockingIPCDiminishCaps_modifies)
              apply simp
              apply (rule threadGet_wp)
             apply simp
             apply (rule threadGet_wp)
            apply (simp del: Collect_const)
            apply (vcg exspec=cap_page_directory_cap_get_capPDBasePtr_spec2)
           apply (rule conseqPre,
                  vcg exspec=cap_page_directory_cap_get_capPDBasePtr_spec2,
                  clarsimp)
          apply simp
          apply (rule getEndpoint_wp)
         apply (simp del: Collect_const)
         apply (vcg exspec=endpoint_ptr_get_epQueue_head_modifies
                    exspec=endpoint_ptr_get_state_modifies)
        apply (simp add: if_1_0_0 getSlotCap_def)
        apply (rule valid_isRight_theRight_split)
        apply simp
        apply (wp getCTE_wp')
        apply (rule validE_R_abstract_rv)
        apply wp
       apply (simp add: if_1_0_0 del: Collect_const)
       apply (vcg exspec=lookup_fp_modifies)
      apply simp
      apply (rule threadGet_wp)
     apply (simp del: Collect_const)
     apply vcg
    apply simp
    apply (rule user_getreg_wp)
   apply simp
   apply (rule user_getreg_wp)
  apply (rule conjI)
   apply (clarsimp simp: obj_at_tcbs_of ct_in_state'_def st_tcb_at_tcbs_of
                         invs_cur' invs_valid_objs' ctes_of_valid')
   apply (frule cte_wp_at_valid_objs_valid_cap', clarsimp)
   apply (clarsimp simp: isCap_simps valid_cap'_def maskCapRights_def)
   apply (clarsimp simp add:obj_at'_def projectKO_eq)
   apply (frule invs_valid_objs')
   apply (erule valid_objsE')
    apply simp
   apply (clarsimp simp:projectKO_opt_ep split:Structures_H.kernel_object.splits)
   apply (clarsimp simp:isRecvEP_def valid_obj'_def valid_ep'_def
     split:Structures_H.endpoint.split_asm)
   apply (erule not_NilE)
   apply (drule_tac x = x in bspec)
    apply fastforce
   apply (clarsimp simp:obj_at_tcbs_of)
   apply (frule_tac ptr2 = x in tcbs_of_aligned')
    apply (simp add:invs_pspace_aligned')
   apply (frule_tac ptr2 = x in tcbs_of_cte_wp_at_vtable)
   apply (clarsimp simp:size_of_def field_simps word_sless_def word_sle_def
      dest!:ptr_val_tcb_ptr_mask2[unfolded mask_def, simplified])
   apply (frule_tac p="x + offs" for offs in ctes_of_valid', clarsimp)
   apply (clarsimp simp: isCap_simps valid_cap'_def invs_valid_pde_mappings'
                  dest!: isValidVTableRootD)
   apply (clarsimp simp: invs_sym'
                         cte_wp_at_ctes_of tcbCallerSlot_def
                         tcbVTableSlot_def tcbReplySlot_def
                         conj_comms tcb_cnode_index_defs field_simps
                         obj_at_tcbs_of)
   apply (clarsimp simp: cte_level_bits_def isValidVTableRoot_def
                         ArchVSpace_H.isValidVTableRoot_def
                         capAligned_def objBits_simps)
   apply (simp cong: conj_cong)
   apply (frule invs_mdb', clarsimp simp: valid_mdb'_def valid_mdb_ctes_def)
   apply (case_tac xb, clarsimp, drule(1) nullcapsD')
   apply (clarsimp simp: pde_stored_asid_def to_bool_def
                         length_msgRegisters word_le_nat_alt[symmetric])
   apply (frule tcb_aligned'[OF obj_at_tcbs_of[THEN iffD2], OF exI, simplified])
   apply clarsimp
   apply (safe del: notI)[1]
     apply (rule not_sym, clarsimp)
     apply (drule aligned_sub_aligned[where x="x + 0x10" and y=x for x])
       apply (erule tcbs_of_aligned')
       apply (simp add:invs_pspace_aligned')
      apply simp
     apply (simp add:is_aligned_def dvd_def)
    apply (clarsimp simp:tcbs_of_def obj_at'_def projectKO_opt_tcb
      split:if_splits Structures_H.kernel_object.splits)
    apply (drule pspace_distinctD')
     apply (simp add:invs_pspace_distinct')
    apply (simp add:objBits_simps)
   apply (clarsimp simp: obj_at_tcbs_of split: list.split)
   apply (erule_tac x = v0 in valid_objsE'[OF invs_valid_objs',rotated])
    apply (clarsimp simp: valid_obj'_def valid_ep'_def isRecvEP_def neq_Nil_conv size_of_def
      split: Structures_H.endpoint.split_asm
      cong: list.case_cong)
    apply (simp add:obj_at_tcbs_of)
   apply simp
  apply (clarsimp simp: syscall_from_H_def[split_simps syscall.split]
                        word_sle_def word_sless_def rf_sr_ksCurThread
                        ptr_val_tcb_ptr_mask' size_of_def cte_level_bits_def
                        tcb_cnode_index_defs tcbCTableSlot_def tcbVTableSlot_def
                        tcbReplySlot_def tcbCallerSlot_def
              simp del: Collect_const split del: split_if)
  apply (drule(1) obj_at_cslift_tcb)
  apply (clarsimp simp: ccte_relation_eq_ccap_relation of_bl_from_bool from_bool_0
                        if_1_0_0 ccap_relation_case_sum_Null_endpoint
                        isRight_case_sum typ_heap_simps')
  apply (frule(1) cap_get_tag_isCap[THEN iffD2])
  apply (clarsimp simp: typ_heap_simps' ccap_relation_ep_helpers)
  apply (erule cmap_relationE1[OF cmap_relation_ep],
         erule ko_at_projectKO_opt)
  apply (frule(1) ko_at_valid_ep')
  apply (clarsimp simp: cendpoint_relation_def Let_def
                        isRecvEP_endpoint_case neq_Nil_conv
                        tcb_queue_relation'_def valid_ep'_def
                        mi_from_H_def)
  apply (clarsimp simp: ccap_relation_ep_helpers from_bool_0
                        isValidVTableRoot_conv
                        cap_get_tag_isCap_ArchObject2
                        ccap_relation_pd_helper)
  apply (clarsimp simp: isCap_simps dest!: isValidVTableRootD)
  done
qed

lemma isMasterReplyCap_fp_conv:
  "ccap_relation cap cap' \<Longrightarrow>
    (index (cap_C.words_C cap') 0 && 0x1F = scast cap_reply_cap)
       = (isReplyCap cap \<and> \<not> capReplyMaster cap)"
  apply (rule trans)
   apply (rule_tac m="mask 4" in split_word_eq_on_mask)
  apply (simp add: cap_get_tag_isCap[symmetric])
  apply (rule conj_cong)
   apply (simp add: mask_def word_bw_assocs cap_get_tag_eq_x
                    cap_reply_cap_def split: split_if)
  apply (clarsimp simp: cap_lift_reply_cap cap_to_H_simps
                        isCap_simps
                 elim!: ccap_relationE)
  apply (simp add: mask_def cap_reply_cap_def word_bw_assocs
                   to_bool_def)
  apply (thin_tac "P" for P)
  apply (rule iffI)
   apply (drule_tac f="\<lambda>v. v >> 4" in arg_cong)
   apply (simp add: shiftr_over_and_dist)
  apply (drule_tac f="\<lambda>v. v << 4" in arg_cong)
  apply (simp add: shiftl_over_and_dist shiftr_shiftl1 mask_def
                   word_bw_assocs)
  done

lemma ccap_relation_reply_helper:
  "\<lbrakk> ccap_relation cap cap'; isReplyCap cap \<rbrakk>
     \<Longrightarrow> cap_reply_cap_CL.capTCBPtr_CL (cap_reply_cap_lift cap')
           = ptr_val (tcb_ptr_to_ctcb_ptr (capTCBPtr cap))"
  by (clarsimp simp: cap_get_tag_isCap[symmetric]
                     cap_lift_reply_cap cap_to_H_simps
                     cap_reply_cap_lift_def
              elim!: ccap_relationE)

lemma valid_ep_typ_at_lift':
  "\<lbrakk> \<And>p. \<lbrace>typ_at' TCBT p\<rbrace> f \<lbrace>\<lambda>rv. typ_at' TCBT p\<rbrace> \<rbrakk>
      \<Longrightarrow> \<lbrace>\<lambda>s. valid_ep' ep s\<rbrace> f \<lbrace>\<lambda>rv s. valid_ep' ep s\<rbrace>"
  apply (cases ep, simp_all add: valid_ep'_def)
   apply (wp hoare_vcg_const_Ball_lift typ_at_lifts | assumption)+
  done

lemma threadSet_tcbState_valid_objs:
  "\<lbrace>valid_tcb_state' st and valid_objs'\<rbrace>
     threadSet (tcbState_update (\<lambda>_. st)) t
   \<lbrace>\<lambda>rv. valid_objs'\<rbrace>"
  apply (wp threadSet_valid_objs')
  apply (clarsimp simp: valid_tcb'_def tcb_cte_cases_def)
  done

lemma fastpath_reply_wait_ccorres:
  notes hoare_TrueI[simp]
  shows "ccorres dc xfdc
       (\<lambda>s. invs' s \<and> ct_in_state' (op = Running) s
               \<and> obj_at' (\<lambda>tcb. tcbContext tcb capRegister = cptr
                              \<and> tcbContext tcb msgInfoRegister = msginfo)
                     (ksCurThread s) s)
       (UNIV \<inter> {s. cptr_' s = cptr} \<inter> {s. msgInfo_' s = msginfo}) []
       (fastpaths SysReplyWait) (Call fastpath_reply_wait_'proc)"
  proof -
   have [simp]: "Kernel_C.tcbCaller = scast tcbCallerSlot"
     by (simp add:Kernel_C.tcbCaller_def tcbCallerSlot_def)
   have [simp]: "Kernel_C.tcbVTable = scast tcbVTableSlot"
     by (simp add:Kernel_C.tcbVTable_def tcbVTableSlot_def)

  have tcbs_of_cte_wp_at_vtable:
    "\<And>s tcb ptr. tcbs_of s ptr = Some tcb \<Longrightarrow>
    cte_wp_at' \<top> (ptr + 0x10 * tcbVTableSlot) s"
    apply (clarsimp simp:tcbs_of_def cte_at'_obj_at'
      split:if_splits)
    apply (drule_tac x = "0x10 * tcbVTableSlot" in bspec)
     apply (simp add:tcb_cte_cases_def tcbVTableSlot_def)
    apply simp
    done

  have tcbs_of_cte_wp_at_caller:
    "\<And>s tcb ptr. tcbs_of s ptr = Some tcb \<Longrightarrow>
    cte_wp_at' \<top> (ptr + 0x10 * tcbCallerSlot) s"
    apply (clarsimp simp:tcbs_of_def cte_at'_obj_at'
      split:if_splits)
    apply (drule_tac x = "0x10 * tcbCallerSlot" in bspec)
     apply (simp add:tcb_cte_cases_def tcbCallerSlot_def)
    apply simp
    done

  have tcbs_of_aligned':
    "\<And>s ptr tcb. \<lbrakk>tcbs_of s ptr = Some tcb;pspace_aligned' s\<rbrakk> \<Longrightarrow> is_aligned ptr 9"
    apply (clarsimp simp:tcbs_of_def obj_at'_def split:if_splits)
    apply (drule pspace_alignedD')
    apply simp+
    apply (simp add:projectKO_opt_tcb objBitsKO_def
      split: Structures_H.kernel_object.splits)
    done

  show ?thesis
  using [[goals_limit = 1]]
  apply (cinit lift: cptr_' msgInfo_')
   apply (simp add: catch_liftE_bindE unlessE_throw_catch_If
                    unifyFailure_catch_If catch_liftE
                    getMessageInfo_def alternative_bind
              cong: if_cong call_ignore_cong del: Collect_const)
   apply (rule ccorres_pre_getCurThread)
   apply (rename_tac curThread)
   apply (rule ccorres_symb_exec_l3[OF _ user_getreg_inv' _ empty_fail_user_getreg])+
     apply (rename_tac msginfo' cptr')
     apply (rule_tac P="msginfo' = msginfo \<and> cptr' = cptr" in ccorres_gen_asm)
     apply (simp del: Collect_const cong: call_ignore_cong)
     apply (simp only:)
     apply (csymbr, csymbr)
     apply (rule_tac r'="\<lambda>ft ft'. (ft' = scast fault_null_fault) = (ft = None)"
               and xf'="fault_type_'" in ccorres_split_nothrow)
         apply (rule_tac P="cur_tcb' and (\<lambda>s. curThread = ksCurThread s)"
                   in ccorres_from_vcg[where P'=UNIV])
         apply (rule allI, rule conseqPre, vcg)
         apply (clarsimp simp: cur_tcb'_def rf_sr_ksCurThread)
         apply (drule(1) obj_at_cslift_tcb, clarsimp)
         apply (clarsimp simp: typ_heap_simps' ctcb_relation_def cfault_rel_def)
         apply (rule rev_bexI, erule threadGet_eq)
         apply (clarsimp simp: fault_lift_def Let_def split: split_if_asm)
        apply ceqv
       apply csymbr
       apply (simp only:)
       apply (rule ccorres_Cond_rhs_Seq)
        apply (rule ccorres_alternative2)
        apply (rule ccorres_split_throws)
         apply (fold dc_def)[1]
         apply (rule ccorres_call_hSkip)
           apply (rule slowpath_ccorres)
          apply simp
         apply simp
        apply (vcg exspec=slowpath_noreturn_spec)
       apply (rule ccorres_alternative1)
       apply (rule ccorres_if_lhs[rotated])
        apply (rule ccorres_inst[where P=\<top> and P'=UNIV])
        apply simp
       apply (simp del: Collect_const cong: call_ignore_cong)
       apply (elim conjE)
       apply (simp add: getThreadCSpaceRoot_def locateSlot_conv
                   del: Collect_const cong: call_ignore_cong)
       apply (rule ccorres_pre_getCTE2)
       apply (rule ccorres_Guard_Seq)
       apply (ctac add: lookup_fp_ccorres)
         apply (rename_tac luRet ep_cap)
         apply (csymbr, csymbr)
         apply (simp add: ccap_relation_case_sum_Null_endpoint
                          of_bl_from_bool from_bool_0
                     del: Collect_const cong: call_ignore_cong)
         apply (rule ccorres_Cond_rhs_Seq)
          apply (simp add: if_1_0_0 cong: if_cong)
          apply (rule ccorres_cond_true_seq)
          apply (rule ccorres_split_throws)
           apply (fold dc_def)[1]
           apply (rule ccorres_call_hSkip)
             apply (rule slowpath_ccorres, simp+)
          apply (vcg exspec=slowpath_noreturn_spec)
         apply (rule ccorres_rhs_assoc)+
         apply csymbr+
         apply (simp add: if_1_0_0 isRight_case_sum
                     del: Collect_const cong: call_ignore_cong)
         apply (elim conjE)
         apply (frule(1) cap_get_tag_isCap[THEN iffD2])
         apply (simp add: ccap_relation_ep_helpers from_bool_0
                     del: Collect_const cong: call_ignore_cong)
         apply (rule ccorres_Cond_rhs_Seq)
          apply simp
          apply (rule ccorres_split_throws)
           apply (fold dc_def)[1]
           apply (rule ccorres_call_hSkip)
             apply (rule slowpath_ccorres, simp+)
          apply (vcg exspec=slowpath_noreturn_spec)
         apply (simp del: Collect_const cong: call_ignore_cong)
         apply (csymbr, csymbr)
         apply (simp add: ccap_relation_ep_helpers
                     del: Collect_const cong: call_ignore_cong)
         apply (rule_tac xf'="ret__unsigned_long_'"
                      and r'="\<lambda>ep v. (v = scast EPState_Send) = isSendEP ep"
                     in ccorres_split_nothrow)
             apply (rule ccorres_add_return2)
             apply (rule ccorres_pre_getEndpoint, rename_tac ep)
             apply (rule_tac P="ko_at' ep (capEPPtr (theRight luRet)) and valid_objs'"
                          in ccorres_from_vcg[where P'=UNIV])
             apply (rule allI, rule conseqPre, vcg)
             apply (clarsimp simp: return_def)
             apply (erule cmap_relationE1[OF cmap_relation_ep], erule ko_at_projectKO_opt)
             apply (clarsimp simp: typ_heap_simps')
             apply (simp add: cendpoint_relation_def Let_def isSendEP_def
                              endpoint_state_defs
                       split: endpoint.split_asm)
            apply ceqv
           apply (rename_tac send_ep send_ep_is_send)
           apply (rule_tac P="ko_at' send_ep (capEPPtr (theRight luRet))
                                and valid_objs'" in ccorres_cross_over_guard)
           apply (simp del: Collect_const cong: call_ignore_cong)
           apply (rule ccorres_Cond_rhs_Seq)
            apply simp
            apply (rule ccorres_split_throws)
             apply (fold dc_def)[1]
             apply (rule ccorres_call_hSkip)
               apply (rule slowpath_ccorres, simp+)
            apply (vcg exspec=slowpath_noreturn_spec)
           apply (simp add: getThreadVSpaceRoot_def locateSlot_conv
                            getThreadCallerSlot_def
                       del: Collect_const cong: if_cong call_ignore_cong)
           apply (rule ccorres_Guard_Seq)+
           apply (rule_tac xf'="ksCurThread_' \<circ> globals"
                       and val="tcb_ptr_to_ctcb_ptr curThread"
                       in ccorres_abstract_known)
            apply (rule Seq_weak_ceqv, rule Basic_ceqv)
            apply (rule rewrite_xfI, clarsimp simp only: o_def)
            apply (rule refl)
           apply csymbr
           apply (rule ccorres_move_c_guard_cte)
           apply (rule_tac var="callerCap_'" and var_update="callerCap_'_update"
                        in getCTE_h_val_ccorres_split[where P=\<top>])
             apply simp
            apply ceqv
           apply (rename_tac caller_cap caller_cap_c)
           apply (rule_tac P="\<lambda>_. capAligned (cteCap caller_cap)"
                        in ccorres_cross_over_guard)
           apply (rule ccorres_Guard_Seq)+
           apply (simp add: isMasterReplyCap_fp_conv
                       del: Collect_const cong: call_ignore_cong)
           apply (rule ccorres_Cond_rhs_Seq)
            apply (simp cong: conj_cong)
            apply (rule ccorres_split_throws)
             apply (fold dc_def)[1]
             apply (rule ccorres_call_hSkip)
               apply (rule slowpath_ccorres, simp+)
            apply (vcg exspec=slowpath_noreturn_spec)
           apply (simp del: Collect_const cong: call_ignore_cong)
           apply (csymbr, csymbr)
           apply (rule_tac r'="\<lambda>ft ft'. (ft' = scast fault_null_fault) = (ft = None)"
                    and xf'="fault_type_'" in ccorres_split_nothrow)
               apply (rule threadGet_vcg_corres)
               apply (rule allI, rule conseqPre, vcg)
               apply (clarsimp simp: obj_at_tcbs_of)
               apply (clarsimp simp: typ_heap_simps' ctcb_relation_def cfault_rel_def
                                     ccap_relation_reply_helper)
               apply (clarsimp simp: fault_lift_def Let_def split: split_if_asm)
              apply ceqv
             apply (simp del: Collect_const not_None_eq cong: call_ignore_cong)
             apply (rule ccorres_Cond_rhs_Seq)
              apply (simp del: Collect_const not_None_eq)
              apply (rule ccorres_split_throws)
               apply (fold dc_def)[1]
               apply (rule ccorres_call_hSkip)
                 apply (rule slowpath_ccorres, simp+)
              apply (vcg exspec=slowpath_noreturn_spec)
             apply (simp del: Collect_const cong: call_ignore_cong)
           apply (rule ccorres_move_c_guard_cte)
           apply (rule ccorres_move_const_guards)+
           apply (rule_tac var="newVTable_'" and var_update="newVTable_'_update"
                          in getCTE_h_val_ccorres_split[where P=\<top>])
               apply simp
              apply ceqv
             apply (rename_tac pd_cap pd_cap_c)
             apply (rule ccorres_symb_exec_r)
               apply (rule_tac xf'=ret__unsigned_long_' in ccorres_abstract, ceqv)
               apply (rename_tac pd_cap_c_ptr_maybe)
               apply csymbr+
               apply (simp add: isValidVTableRoot_conv from_bool_0
                           del: Collect_const cong: call_ignore_cong)
               apply (rule ccorres_Cond_rhs_Seq)
                apply simp
                apply (rule ccorres_split_throws)
                 apply (fold dc_def)[1]
                 apply (rule ccorres_call_hSkip)
                   apply (rule slowpath_ccorres, simp+)
                apply (vcg exspec=slowpath_noreturn_spec)
               apply (simp del: Collect_const cong: call_ignore_cong)
               apply (drule isValidVTableRootD)
               apply (rule_tac P="pd_cap_c_ptr_maybe = capUntypedPtr (cteCap pd_cap)"
                           in ccorres_gen_asm2)
               apply (simp add: ccap_relation_pd_helper cap_get_tag_isCap_ArchObject2
                                ccap_relation_reply_helper
                           del: Collect_const WordSetup.ptr_add_def cong: call_ignore_cong)
               apply (rule stored_hw_asid_get_ccorres_split[where P=\<top>], ceqv)
               apply (rule ccorres_move_c_guard_tcb ccorres_Guard_Seq)+
               apply (rule ccorres_symb_exec_l3[OF _ threadGet_inv _ empty_fail_threadGet])
                apply (rule ccorres_symb_exec_l3[OF _ threadGet_inv _ empty_fail_threadGet])
                 apply (rename_tac curPrio destPrio)
                 apply (rule ccorres_seq_cond_raise[THEN iffD2])
                 apply (rule_tac R="obj_at' (op = curPrio \<circ> tcbPriority) curThread
                                     and obj_at' (op = destPrio \<circ> tcbPriority)
                                               (capTCBPtr (cteCap caller_cap))
                                     and (\<lambda>s. ksCurThread s = curThread)"
                                in ccorres_cond2')
                   apply clarsimp
                   apply (drule(1) obj_at_cslift_tcb)+
                   apply (clarsimp simp: typ_heap_simps' rf_sr_ksCurThread)
                   apply (simp add: ctcb_relation_unat_tcbPriority_C
                                    word_less_nat_alt linorder_not_le)
                  apply simp
                  apply (rule ccorres_split_throws)
                   apply (fold dc_def)[1]
                   apply (rule ccorres_call_hSkip)
                     apply (rule slowpath_ccorres, simp+)
                  apply (vcg exspec=slowpath_noreturn_spec)
                 apply (simp del: Collect_const cong: call_ignore_cong)
                 apply csymbr+
                 apply (rule ccorres_symb_exec_l3[OF _ gets_inv _ empty_fail_gets])
                  apply (rename_tac asidMap)
                  apply (rule_tac P="asid_map_pd_to_hwasids asidMap (capPDBasePtr (capCap ((cteCap pd_cap))))
                                        = set_option (pde_stored_asid shw_asid)" in ccorres_gen_asm)
                  apply (simp del: Collect_const cong: call_ignore_cong)
                  apply (rule ccorres_Cond_rhs_Seq)
                   apply (simp add: pde_stored_asid_def asid_map_pd_to_hwasids_def)
                   apply (rule ccorres_split_throws)
                    apply (fold dc_def)[1]
                    apply (rule ccorres_call_hSkip)
                      apply (rule slowpath_ccorres, simp+)
                   apply (vcg exspec=slowpath_noreturn_spec)
                  apply (simp add: pde_stored_asid_def asid_map_pd_to_hwasids_def
                                   to_bool_def
                              del: Collect_const cong: call_ignore_cong)

                  apply (rule ccorres_move_c_guard_tcb ccorres_Guard_Seq)+
                  apply (rule ccorres_symb_exec_l3[OF _ curDomain_inv _])
                    prefer 3
                    apply (simp only: curDomain_def, rule empty_fail_gets)
                   apply (rule ccorres_symb_exec_l3[OF _ threadGet_inv _ empty_fail_threadGet])
                    apply (rename_tac curDom destDom)

                    apply (rule ccorres_seq_cond_raise[THEN iffD2])
                    apply (rule_tac R="obj_at' (op = destDom \<circ> tcbDomain)
                                                  (capTCBPtr (cteCap caller_cap))
                                        and (\<lambda>s. ksCurDomain s = curDom)"
                                   in ccorres_cond2')
                      apply clarsimp
                      apply (drule(1) obj_at_cslift_tcb)+
                      apply (clarsimp simp: typ_heap_simps' rf_sr_ksCurDomain)
                      apply (drule ctcb_relation_tcbDomain[symmetric])
                      apply (clarsimp simp: up_ucast_inj_eq[symmetric] maxDom_def)

                     apply simp
                     apply (rule ccorres_split_throws)
                      apply (fold dc_def)[1]
                      apply (rule ccorres_call_hSkip)
                        apply (rule slowpath_ccorres, simp+)
                     apply (vcg exspec=slowpath_noreturn_spec)
                    apply (simp del: Collect_const cong: call_ignore_cong)

                  apply (rule ccorres_rhs_assoc2, rule ccorres_rhs_assoc2)
                  apply (rule_tac xf'=xfdc and r'=dc in ccorres_split_nothrow)
                      apply (rule_tac P="capAligned (theRight luRet)" in ccorres_gen_asm)
                      apply (rule_tac P=\<top> and P'="\<lambda>s. ksCurThread s = curThread"
                                 in threadSet_ccorres_lemma3)
                       apply vcg
                      apply (clarsimp simp: rf_sr_ksCurThread typ_heap_simps'
                                            h_t_valid_clift_Some_iff)
                      apply (clarsimp simp: capAligned_def isCap_simps objBits_simps
                                            "StrictC'_thread_state_defs" mask_def)
                      apply (simp add: ccap_relation_ep_helpers)
                      apply (clarsimp simp: if_distrib[where f=scast] if_Const_helper[where Con="\<lambda>x. x && 1", symmetric])
                      apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                                            typ_heap_simps')
                      apply (rule conjI)
                       apply (clarsimp simp: cpspace_relation_def typ_heap_simps'
                                             update_tcb_map_tos map_to_tcbs_upd)
                       apply (subst map_to_ctes_upd_tcb_no_ctes, assumption)
                        apply (rule ball_tcb_cte_casesI, simp_all)[1]
                       apply (simp add: cep_relations_drop_fun_upd)
                       apply (erule cmap_relation_updI, erule ko_at_projectKO_opt)
                        apply (simp add: ctcb_relation_def cthread_state_relation_def
                                         "StrictC'_thread_state_defs" from_bool_0
                                         to_bool_def if_1_0_0)
                       apply simp
                      apply (rule conjI, erule cready_queues_relation_not_queue_ptrs)
                        apply (rule ext, simp split: split_if)
                       apply (rule ext, simp split: split_if)
                      apply (simp add: carch_state_relation_def cmachine_state_relation_def
                                       h_t_valid_clift_Some_iff)
                     apply ceqv
                    apply (rule ccorres_rhs_assoc2, rule ccorres_rhs_assoc2)
                    apply (rule_tac xf'=xfdc and r'=dc in ccorres_split_nothrow)
                        apply (rule fastpath_enqueue_ccorres[unfolded o_def])
                        apply simp
                       apply ceqv
                      apply (simp add: liftM_def del: Collect_const cong: call_ignore_cong)
                      apply (rule_tac r'="\<lambda>rv rv'. rv' = mdbPrev (cteMDBNode rv)"
                                  and xf'=ret__unsigned_long_' in ccorres_split_nothrow)
                          apply (rule_tac P="tcb_at' curThread"
                                       in getCTE_ccorres_helper[where P'=UNIV])
                          apply (rule conseqPre, vcg)
                          apply (clarsimp simp: typ_heap_simps' cte_level_bits_def
                                                tcbCallerSlot_def size_of_def
                                                tcb_cnode_index_defs tcb_ptr_to_ctcb_ptr_mask)
                          apply (clarsimp simp: ccte_relation_def option_map_Some_eq2)
                         apply ceqv
                        apply (rule ccorres_assert)
                        apply (rename_tac mdbPrev_cte mdbPrev_cte_c)
                        apply (rule ccorres_split_nothrow_dc)
                           apply (simp add: updateMDB_def Let_def
                                       del: Collect_const cong: if_cong)
                           apply (rule_tac P="cte_wp_at' (op = mdbPrev_cte)
                                                (curThread + (tcbCallerSlot << cte_level_bits))
                                                 and valid_mdb'"
                                       in ccorres_from_vcg[where P'=UNIV])
                           apply (rule allI, rule conseqPre, vcg)
                           apply (clarsimp simp: cte_wp_at_ctes_of)
                           apply (drule(2) valid_mdb_ctes_of_prev[rotated])
                           apply (clarsimp simp: cte_wp_at_ctes_of)
                           apply (rule cmap_relationE1[OF cmap_relation_cte], assumption+)
                           apply (clarsimp simp: typ_heap_simps' split_def)
                           apply (rule getCTE_setCTE_rf_sr, simp_all)[1]
                           apply (clarsimp simp: ccte_relation_def option_map_Some_eq2
                                                 cte_to_H_def mdb_node_to_H_def
                                                 c_valid_cte_def)
                          apply (rule ccorres_rhs_assoc2, rule ccorres_rhs_assoc2,
                                 rule ccorres_rhs_assoc2)
                          apply (rule ccorres_split_nothrow_dc)
                             apply (rule_tac P="cte_at' (curThread + (tcbCallerSlot << cte_level_bits))
                                                   and tcb_at' curThread"
                                        in ccorres_from_vcg[where P'=UNIV])
                             apply (rule allI, rule conseqPre, vcg)
                             apply (clarsimp simp: cte_wp_at_ctes_of)
                             apply (rule cmap_relationE1[OF cmap_relation_cte], assumption+)
                             apply (clarsimp simp: typ_heap_simps' split_def tcbCallerSlot_def
                                                   tcb_cnode_index_defs tcb_ptr_to_ctcb_ptr_mask
                                                   cte_level_bits_def size_of_def)
                             apply (rule setCTE_rf_sr, simp_all add: typ_heap_simps')[1]
                             apply (clarsimp simp: ccte_relation_eq_ccap_relation makeObject_cte
                                                   mdb_node_to_H_def nullMDBNode_def
                                                   ccap_relation_NullCap_iff)
                            apply csymbr
                            apply (ctac add: fastpath_copy_mrs_ccorres[unfolded forM_x_def])
                              apply (rule_tac r'=dc and xf'=xfdc in ccorres_split_nothrow)
                                  apply (simp add: setThreadState_runnable_simp)
                                  apply (rule_tac P=\<top> in threadSet_ccorres_lemma2, vcg)
                                  apply (clarsimp simp: typ_heap_simps' rf_sr_def
                                                        cstate_relation_def Let_def)
                                  apply (rule conjI)
                                   apply (clarsimp simp: cpspace_relation_def typ_heap_simps'
                                                         update_tcb_map_tos map_to_tcbs_upd)
                                   apply (subst map_to_ctes_upd_tcb_no_ctes, assumption)
                                    apply (rule ball_tcb_cte_casesI, simp_all)[1]
                                   apply (simp add: cep_relations_drop_fun_upd)
                                   apply (erule cmap_relation_updI, erule ko_at_projectKO_opt)
                                    apply (simp add: ctcb_relation_def cthread_state_relation_def)
                                   apply simp
                                  apply (rule conjI, erule cready_queues_relation_not_queue_ptrs)
                                    apply (rule ext, simp split: split_if)
                                   apply (rule ext, simp split: split_if)
                                  apply (simp add: carch_state_relation_def cmachine_state_relation_def
                                                   h_t_valid_clift_Some_iff)
                                 apply ceqv
                                apply (simp only: bind_assoc[symmetric])
                                apply (rule ccorres_split_nothrow_novcg_dc)
                                   apply (rule ccorres_call,
                                          rule_tac v=shw_asid and pd="capUntypedPtr (cteCap pd_cap)"
                                                in switchToThread_fp_ccorres,
                                          simp+)[1]
                                  apply (rule_tac P="\<lambda>s. ksCurThread s = capTCBPtr (cteCap caller_cap)"
                                               in ccorres_cross_over_guard)
                                  apply csymbr
                                  apply csymbr
                                  apply (rule ccorres_call_hSkip)
                                    apply (fold dc_def)[1]
                                    apply (rule fastpath_restore_ccorres)
                                   apply simp
                                  apply simp
                                 apply (simp add: setCurThread_def)
                                 apply wp
                                 apply (rule_tac P=\<top> in hoare_triv, simp)
                                apply (simp add: imp_conjL rf_sr_ksCurThread del: all_imp_to_ex)
                                apply (clarsimp simp: ccap_relation_ep_helpers guard_is_UNIV_def
                                                      mi_from_H_def)
                               apply (simp add: pd_has_hwasid_def)
                               apply (wp sts_ct_in_state_neq' sts_valid_objs')
                              apply (simp del: Collect_const)
                              apply (vcg exspec=thread_state_ptr_set_tsType_np_modifies)
                             apply simp
                             apply (rule mapM_x_wp'[OF hoare_weaken_pre], wp)
                             apply clarsimp
                            apply simp
                            apply (vcg exspec=fastpath_copy_mrs_modifies)
                           apply (simp add: valid_tcb_state'_def)
                           apply wp
                           apply (wp setCTE_cte_wp_at_other)
                          apply (simp del: Collect_const)
                          apply vcg
                         apply (simp add: o_def)
                         apply (wp | simp
                                    | wp_once updateMDB_weak_cte_wp_at
                                    | wp_once updateMDB_cte_wp_at_other)+
                        apply (vcg exspec=mdb_node_ptr_mset_mdbNext_mdbRevocable_mdbFirstBadged_modifies)
                       apply simp
                       apply (wp getCTE_wp')
                      apply simp
                      apply vcg
                     apply (simp add: shiftl_t2n)
                     apply (wp hoare_drop_imps setEndpoint_valid_mdb' set_ep_valid_objs'
                            setObject_no_0_obj'[where 'a=endpoint, folded setEndpoint_def])
                    apply simp
                    apply (vcg exspec=endpoint_ptr_mset_epQueue_tail_state_modifies
                               exspec=endpoint_ptr_set_epQueue_head_np_modifies
                               exspec=endpoint_ptr_get_epQueue_tail_modifies)
                   apply (simp add: valid_pspace'_def pred_conj_def conj_comms
                                    valid_mdb'_def)
                   apply (wp threadSet_cur threadSet_tcbState_valid_objs
                             threadSet_state_refs_of' threadSet_ctes_of
                             valid_ep_typ_at_lift' threadSet_cte_wp_at'
                                | simp)+
                  apply (vcg exspec=thread_state_ptr_set_blockingIPCDiminish_np_modifies
                             exspec=thread_state_ptr_mset_blockingIPCEndpoint_tsType_modifies)

                   apply simp
                   apply (rule threadGet_wp)
                  apply simp
                  apply wp[1]

                 apply simp
                 apply wp
                apply (simp cong: if_cong)
                apply (rule threadGet_wp)
               apply (simp cong: if_cong)
               apply (rule threadGet_wp)
              apply (simp add: syscall_from_H_def del: Collect_const)
              apply (vcg exspec=cap_page_directory_cap_get_capPDBasePtr_spec2)
             apply (rule conseqPre,
                    vcg exspec=cap_page_directory_cap_get_capPDBasePtr_spec2,
                    clarsimp)
            apply (simp add:ccap_relation_reply_helper cong:if_cong)
            apply (rule threadGet_wp)
           apply (simp add: syscall_from_H_def ccap_relation_reply_helper)
           apply (vcg exspec=fault_get_faultType_modifies)
          apply simp
          apply (rule getEndpoint_wp)
         apply (simp add: syscall_from_H_def ccap_relation_reply_helper)
         apply (vcg exspec=endpoint_ptr_get_state_modifies)
        apply (simp add: if_1_0_0 getSlotCap_def)
        apply (rule valid_isRight_theRight_split)
        apply simp
        apply (wp getCTE_wp')
        apply (rule validE_R_abstract_rv)
        apply wp
       apply (simp del: Collect_const)
       apply (vcg exspec=lookup_fp_modifies)
      apply simp
      apply (rule threadGet_wp)
     apply (simp del: Collect_const)
     apply vcg
    apply simp
    apply (rule user_getreg_wp)
   apply simp
   apply (rule user_getreg_wp)
  apply (rule conjI)
   apply (clarsimp simp: ct_in_state'_def obj_at_tcbs_of)
   apply (frule tcbs_of_aligned')
    apply (simp add:invs_pspace_aligned')
   apply (frule tcbs_of_cte_wp_at_caller)
   apply (clarsimp simp:size_of_def field_simps
      dest!:ptr_val_tcb_ptr_mask2[unfolded mask_def])
   apply (frule st_tcb_at_state_refs_ofD')
   apply (clarsimp simp: obj_at_tcbs_of ct_in_state'_def st_tcb_at_tcbs_of
                         invs_cur' invs_valid_objs' ctes_of_valid'
                         fun_upd_def[symmetric] fun_upd_idem)
   apply (frule cte_wp_at_valid_objs_valid_cap', clarsimp)
   apply (clarsimp simp: isCap_simps valid_cap'_def[split_simps capability.split]
                         maskCapRights_def cte_wp_at_ctes_of cte_level_bits_def)
   apply (frule_tac p = a in ctes_of_valid',clarsimp)
    apply (simp add:valid_cap_simps')
   apply (clarsimp simp:cte_level_bits_def)
   apply (frule_tac p="p + tcbCallerSlot * 0x10" for p in ctes_of_valid',clarsimp)
   apply (clarsimp simp: valid_capAligned)
   apply (frule_tac ptr2 = v0a in  tcbs_of_cte_wp_at_vtable)
   apply (frule_tac ptr2 = v0a in tcbs_of_aligned')
    apply (simp add:invs_pspace_aligned')
   apply (clarsimp simp:size_of_def field_simps cte_wp_at_ctes_of
     word_sle_def word_sless_def
     dest!:ptr_val_tcb_ptr_mask2[unfolded mask_def])
   apply (clarsimp simp: valid_cap_simps' obj_at_tcbs_of)
   apply (frule_tac p="p + tcbVTableSlot * 0x10" for p in ctes_of_valid', clarsimp)
   apply (clarsimp simp: isCap_simps valid_cap_simps' capAligned_def
                         invs_valid_pde_mappings' obj_at_tcbs_of
                  dest!: isValidVTableRootD)
   apply (frule invs_mdb')
   apply (clarsimp simp: cte_wp_at_ctes_of tcbSlots cte_level_bits_def
                         makeObject_cte isValidVTableRoot_def
                         ArchVSpace_H.isValidVTableRoot_def
                         pde_stored_asid_def to_bool_def
                         valid_mdb'_def valid_tcb_state'_def
                         word_le_nat_alt[symmetric] length_msgRegisters)
   apply (frule ko_at_valid_ep', clarsimp)
   apply (safe del: notI)[1]
    apply (simp add: isSendEP_def valid_ep'_def tcb_at_invs'
              split: Structures_H.endpoint.split_asm)
    apply (rule subst[OF epQueue.simps(1)],
           erule st_tcb_at_not_in_ep_queue[where P="op = Running", rotated],
           clarsimp+)
    apply (simp add: obj_at_tcbs_of st_tcb_at_tcbs_of)
   apply (clarsimp simp: field_simps)
  apply (clarsimp simp: syscall_from_H_def[split_simps syscall.split]
                        word_sle_def word_sless_def rf_sr_ksCurThread
                        ptr_val_tcb_ptr_mask' size_of_def cte_level_bits_def
                        tcb_cnode_index_defs tcbSlots
              simp del: Collect_const)
  apply (drule(1) obj_at_cslift_tcb)
  apply (clarsimp simp: ccte_relation_eq_ccap_relation of_bl_from_bool from_bool_0
                        if_1_0_0 ccap_relation_case_sum_Null_endpoint
                        isRight_case_sum typ_heap_simps'
                        cap_get_tag_isCap mi_from_H_def)
  apply (clarsimp simp: isCap_simps capAligned_def objBits_simps
                 dest!: ptr_val_tcb_ptr_mask2[unfolded mask_def])
  apply (clarsimp simp: ccap_relation_pd_helper cap_get_tag_isCap_ArchObject2
                 dest!: isValidVTableRootD)
  apply (clarsimp simp: isCap_simps)
  done
qed

end

datatype tcb_state_regs = TCBStateRegs "thread_state" "ARMMachineTypes.register \<Rightarrow> machine_word"

definition
 "tsrContext tsr \<equiv> case tsr of TCBStateRegs ts regs \<Rightarrow> regs"

definition
 "tsrState tsr \<equiv> case tsr of TCBStateRegs ts regs \<Rightarrow> ts"

lemma accessors_TCBStateRegs[simp]:
  "TCBStateRegs (tsrState v) (tsrContext v) = v"
  by (cases v, simp add: tsrState_def tsrContext_def)

lemma tsrContext_simp[simp]:
  "tsrContext (TCBStateRegs st con) = con"
  by (simp add: tsrContext_def)

lemma tsrState_simp[simp]:
  "tsrState (TCBStateRegs st con) = st"
  by (simp add: tsrState_def)

definition
  get_tcb_state_regs :: "kernel_object option \<Rightarrow> tcb_state_regs"
where
 "get_tcb_state_regs oko \<equiv> case oko of
    Some (KOTCB tcb) \<Rightarrow> TCBStateRegs (tcbState tcb) (tcbContext tcb)"

definition
  put_tcb_state_regs_tcb :: "tcb_state_regs \<Rightarrow> tcb \<Rightarrow> tcb"
where
 "put_tcb_state_regs_tcb tsr tcb \<equiv> case tsr of
     TCBStateRegs st regs \<Rightarrow> tcb \<lparr> tcbState := st, tcbContext := regs \<rparr>"

definition
  put_tcb_state_regs :: "tcb_state_regs \<Rightarrow> kernel_object option \<Rightarrow> kernel_object option"
where
 "put_tcb_state_regs tsr oko = Some (KOTCB (put_tcb_state_regs_tcb tsr
    (case oko of
       Some (KOTCB tcb) \<Rightarrow> tcb | _ \<Rightarrow> makeObject)))"

definition
 "partial_overwrite idx tcbs ps \<equiv>
     \<lambda>x. if x \<in> range idx
         then put_tcb_state_regs (tcbs (inv idx x)) (ps x)
         else ps x"

definition
  isolate_thread_actions :: "('x \<Rightarrow> word32) \<Rightarrow> 'a kernel
                               \<Rightarrow> (('x \<Rightarrow> tcb_state_regs) \<Rightarrow> ('x \<Rightarrow> tcb_state_regs))
                               \<Rightarrow> (scheduler_action \<Rightarrow> scheduler_action)
                               \<Rightarrow> 'a kernel"
where
 "isolate_thread_actions idx m t f \<equiv> do
    s \<leftarrow> gets (ksSchedulerAction_update (\<lambda>_. ResumeCurrentThread)
                    o ksPSpace_update (partial_overwrite idx (K undefined)));
    tcbs \<leftarrow> gets (\<lambda>s. get_tcb_state_regs o ksPSpace s o idx);
    sa \<leftarrow> getSchedulerAction;
    (rv, s') \<leftarrow> select_f (m s);
    modify (\<lambda>s. ksPSpace_update (partial_overwrite idx (t tcbs))
                    (s' \<lparr> ksSchedulerAction := f sa \<rparr>));
    return rv
  od"

lemma put_tcb_state_regs_twice[simp]:
  "put_tcb_state_regs tsr (put_tcb_state_regs tsr' tcb)
    = put_tcb_state_regs tsr tcb"
  apply (simp add: put_tcb_state_regs_def put_tcb_state_regs_tcb_def
                   makeObject_tcb
            split: tcb_state_regs.split option.split
                   Structures_H.kernel_object.split)
  apply (intro all_tcbI impI allI)
  apply simp
  done

lemma partial_overwrite_twice[simp]:
  "partial_overwrite idx f (partial_overwrite idx g ps)
       = partial_overwrite idx f ps"
  by (rule ext, simp add: partial_overwrite_def)

lemma get_tcb_state_regs_partial_overwrite[simp]:
  "inj idx \<Longrightarrow>
   get_tcb_state_regs (partial_overwrite idx tcbs f (idx x))
      = tcbs x"
  apply (simp add: partial_overwrite_def)
  apply (simp add: put_tcb_state_regs_def
                   get_tcb_state_regs_def
                   put_tcb_state_regs_tcb_def
            split: tcb_state_regs.split)
  done

lemma isolate_thread_actions_bind:
  "inj idx \<Longrightarrow>
   isolate_thread_actions idx a b c >>=
              (\<lambda>x. isolate_thread_actions idx (d x) e f)
      = isolate_thread_actions idx a id id
          >>= (\<lambda>x. isolate_thread_actions idx (d x) (e o b) (f o c))"
  apply (rule ext)
  apply (clarsimp simp: isolate_thread_actions_def bind_assoc split_def
                        bind_select_f_bind[symmetric])
  apply (clarsimp simp: exec_gets getSchedulerAction_def)
  apply (rule select_bind_eq)
  apply (simp add: exec_gets exec_modify o_def)
  apply (rule select_bind_eq)
  apply (simp add: exec_gets exec_modify)
  done

context kernel_m begin

lemma getObject_return:
  fixes v :: "'a :: pspace_storable" shows
  "\<lbrakk> \<And>a b c d. (loadObject a b c d :: 'a kernel) = loadObject_default a b c d;
        ko_at' v p s; (1 :: word32) < 2 ^ objBits v \<rbrakk> \<Longrightarrow> getObject p s = return v s"
  apply (clarsimp simp: getObject_def split_def exec_gets
                        obj_at'_def projectKOs lookupAround2_known1
                        assert_opt_def loadObject_default_def)
  apply (simp add: projectKO_def alignCheck_assert)
  apply (simp add: project_inject objBits_def)
  apply (frule(2) in_magnitude_check[where s'=s])
  apply (simp add: magnitudeCheck_assert in_monad)
  done

lemma setObject_modify:
  fixes v :: "'a :: pspace_storable" shows
  "\<lbrakk> obj_at' (P :: 'a \<Rightarrow> bool) p s; updateObject v = updateObject_default v;
         (1 :: word32) < 2 ^ objBits v \<rbrakk>
    \<Longrightarrow> setObject p v s
      = modify (ksPSpace_update (\<lambda>ps. ps (p \<mapsto> injectKO v))) s"
  apply (clarsimp simp: setObject_def split_def exec_gets
                        obj_at'_def projectKOs lookupAround2_known1
                        assert_opt_def updateObject_default_def
                        bind_assoc)
  apply (simp add: projectKO_def alignCheck_assert)
  apply (simp add: project_inject objBits_def)
  apply (clarsimp simp only: objBitsT_koTypeOf[symmetric] koTypeOf_injectKO)
  apply (frule(2) in_magnitude_check[where s'=s])
  apply (simp add: magnitudeCheck_assert in_monad)
  apply (simp add: simpler_modify_def)
  done

lemmas getObject_return_tcb
    = getObject_return[OF meta_eq_to_obj_eq, OF loadObject_tcb,
                       unfolded objBits_simps, simplified]

lemmas setObject_modify_tcb
    = setObject_modify[OF _ meta_eq_to_obj_eq, OF _ updateObject_tcb,
                       unfolded objBits_simps, simplified]

lemma partial_overwrite_fun_upd:
  "inj idx \<Longrightarrow>
   partial_overwrite idx (tsrs (x := y))
    = (\<lambda>ps. (partial_overwrite idx tsrs ps) (idx x := put_tcb_state_regs y (ps (idx x))))"
  apply (intro ext, simp add: partial_overwrite_def)
  apply (clarsimp split: split_if)
  done

lemma get_tcb_state_regs_ko_at':
  "ko_at' ko p s \<Longrightarrow> get_tcb_state_regs (ksPSpace s p)
       = TCBStateRegs (tcbState ko) (tcbContext ko)"
  by (clarsimp simp: obj_at'_def projectKOs get_tcb_state_regs_def)

lemma put_tcb_state_regs_ko_at':
  "ko_at' ko p s \<Longrightarrow> put_tcb_state_regs tsr (ksPSpace s p)
       = Some (KOTCB (ko \<lparr> tcbState := tsrState tsr, tcbContext := tsrContext tsr \<rparr>))"
  by (clarsimp simp: obj_at'_def projectKOs put_tcb_state_regs_def
                     put_tcb_state_regs_tcb_def
              split: tcb_state_regs.split)

lemma partial_overwrite_get_tcb_state_regs:
  "\<lbrakk> \<forall>x. tcb_at' (idx x) s; inj idx \<rbrakk> \<Longrightarrow>
   partial_overwrite idx (\<lambda>x. get_tcb_state_regs (ksPSpace s (idx x)))
                (ksPSpace s) = ksPSpace s"
  apply (rule ext, simp add: partial_overwrite_def
                      split: split_if)
  apply clarsimp
  apply (drule_tac x=xa in spec)
  apply (clarsimp simp: obj_at'_def projectKOs put_tcb_state_regs_def
                        get_tcb_state_regs_def put_tcb_state_regs_tcb_def)
  apply (case_tac obj, simp)
  done

lemma ksPSpace_update_partial_id:
  "\<lbrakk> \<And>ps x. f ps x = ps (idx x) \<or> f ps x = ksPSpace s (idx x);
       \<forall>x. tcb_at' (idx x) s; inj idx \<rbrakk> \<Longrightarrow>
   ksPSpace_update (\<lambda>ps. partial_overwrite idx (\<lambda>x. get_tcb_state_regs (f ps x)) ps) s
      = s"
  apply (rule trans, rule kernel_state.fold_congs[OF refl refl])
   apply (erule_tac x="ksPSpace s" in meta_allE)
   apply (clarsimp simp: partial_overwrite_get_tcb_state_regs)
   apply (rule refl)
  apply simp
  done

lemma isolate_thread_actions_asUser:
  "\<lbrakk> idx t' = t; inj idx; f = (\<lambda>s. ({(v, g s)}, False)) \<rbrakk> \<Longrightarrow>
   monadic_rewrite False True (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
      (asUser t f)
      (isolate_thread_actions idx (return v)
           (\<lambda>tsrs. (tsrs (t' := TCBStateRegs (tsrState (tsrs t'))
                                    (g (tsrContext (tsrs t'))))))
            id)"
  apply (simp add: asUser_def liftM_def isolate_thread_actions_def split_def
                   select_f_returns bind_assoc select_f_singleton_return
                   threadGet_def threadSet_def)
  apply (clarsimp simp: monadic_rewrite_def)
  apply (frule_tac x=t' in spec)
  apply (drule obj_at_ko_at', clarsimp)
  apply (simp add: exec_gets getSchedulerAction_def exec_modify
                   getObject_return_tcb setObject_modify_tcb o_def
             cong: bind_apply_cong)+
  apply (simp add: partial_overwrite_fun_upd return_def get_tcb_state_regs_ko_at')
  apply (rule kernel_state.fold_congs[OF refl refl])
  apply (clarsimp simp: partial_overwrite_get_tcb_state_regs
                        put_tcb_state_regs_ko_at')
  apply (case_tac ko, simp)
  done

lemma getRegister_simple:
  "getRegister r = (\<lambda>con. ({(con r, con)}, False))"
  by (simp add: getRegister_def simpler_gets_def)

lemma mapM_getRegister_simple:
  "mapM getRegister rs = (\<lambda>con. ({(map con rs, con)}, False))"
  apply (induct rs)
   apply (simp add: mapM_Nil return_def)
  apply (simp add: mapM_Cons getRegister_def simpler_gets_def
                   bind_def return_def)
  done

lemma setRegister_simple:
  "setRegister r v = (\<lambda>con. ({((), con (r := v))}, False))"
  by (simp add: setRegister_def simpler_modify_def)

lemma zipWithM_setRegister_simple:
  "zipWithM_x setRegister rs vs
      = (\<lambda>con. ({((), foldl (\<lambda>con (r, v). con (r := v)) con (zip rs vs))}, False))"
  apply (simp add: zipWithM_x_mapM_x)
  apply (induct ("zip rs vs"))
   apply (simp add: mapM_x_Nil return_def)
  apply (clarsimp simp add: mapM_x_Cons bind_def setRegister_def
                            simpler_modify_def fun_upd_def[symmetric])
  done

lemma dom_partial_overwrite:
  "\<forall>x. tcb_at' (idx x) s \<Longrightarrow> dom (partial_overwrite idx tsrs (ksPSpace s))
       = dom (ksPSpace s)"
  apply (rule set_eqI)
  apply (clarsimp simp: dom_def partial_overwrite_def put_tcb_state_regs_def
                 split: split_if)
  apply (fastforce elim!: obj_atE')
  done

lemma map_to_ctes_partial_overwrite:
  "\<forall>x. tcb_at' (idx x) s \<Longrightarrow>
   map_to_ctes (partial_overwrite idx tsrs (ksPSpace s))
     = ctes_of s"
  apply (rule ext)
  apply (frule dom_partial_overwrite[where tsrs=tsrs])
  apply (simp add: map_to_ctes_def partial_overwrite_def
                   Let_def)
  apply (case_tac "x \<in> range idx")
   apply (clarsimp simp: put_tcb_state_regs_def)
   apply (drule_tac x=xa in spec)
   apply (clarsimp simp: obj_at'_def projectKOs objBits_simps
                   cong: if_cong)
   apply (simp add: put_tcb_state_regs_def put_tcb_state_regs_tcb_def
                    objBits_simps
              cong: if_cong option.case_cong)
   apply (case_tac obj, simp split: tcb_state_regs.split split_if)
  apply simp
  apply (rule if_cong[OF refl])
   apply simp
  apply (case_tac "x && ~~ mask (objBitsKO (KOTCB undefined)) \<in> range idx")
   apply (clarsimp simp: put_tcb_state_regs_def)
   apply (drule_tac x=xa in spec)
   apply (clarsimp simp: obj_at'_def projectKOs objBits_simps
                   cong: if_cong)
   apply (simp add: put_tcb_state_regs_def put_tcb_state_regs_tcb_def
                    objBits_simps
              cong: if_cong option.case_cong)
   apply (case_tac obj, simp split: tcb_state_regs.split split_if)
   apply (intro impI allI)
   apply (subgoal_tac "x - idx xa = x && mask 9")
    apply (clarsimp simp: tcb_cte_cases_def split: split_if)
   apply (drule_tac t = "idx xa" in sym)
    apply simp
  apply (simp cong: if_cong)
  done

definition
 "thread_actions_isolatable idx f =
    (inj idx \<longrightarrow> monadic_rewrite False True (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
                   f (isolate_thread_actions idx f id id))"

lemma getCTE_assert_opt:
  "getCTE p = gets (\<lambda>s. ctes_of s p) >>= assert_opt"
  apply (intro ext)
  apply (simp add: exec_gets assert_opt_def Pair_fst_snd_eq
                   fail_def return_def
            split: option.split)
  apply (rule conjI)
   apply clarsimp
   apply (rule context_conjI)
    apply (rule ccontr, clarsimp elim!: nonemptyE)
    apply (frule use_valid[OF _ getCTE_sp], rule TrueI)
    apply (frule in_inv_by_hoareD[OF getCTE_inv])
    apply (clarsimp simp: cte_wp_at_ctes_of)
   apply (simp add: empty_failD[OF empty_fail_getCTE])
  apply clarsimp
  apply (simp add: no_failD[OF no_fail_getCTE, OF ctes_of_cte_at])
  apply (subgoal_tac "cte_wp_at' (op = x2) p x")
   apply (clarsimp simp: cte_wp_at'_def getCTE_def)
  apply (simp add: cte_wp_at_ctes_of)
  done

lemma getCTE_isolatable:
  "thread_actions_isolatable idx (getCTE p)"
  apply (clarsimp simp: thread_actions_isolatable_def)
  apply (simp add: isolate_thread_actions_def bind_assoc split_def)
  apply (simp add: getCTE_assert_opt bind_select_f_bind[symmetric]
                   bind_assoc select_f_returns)
  apply (clarsimp simp: monadic_rewrite_def exec_gets getSchedulerAction_def
                        map_to_ctes_partial_overwrite)
  apply (simp add: assert_opt_def select_f_returns select_f_asserts
            split: option.split)
  apply (clarsimp simp: exec_modify o_def return_def)
  apply (simp add: ksPSpace_update_partial_id)
  done

lemma objBits_2n:
  "(1 :: word32) < 2 ^ objBits obj"
  by (simp add: objBits_def objBitsKO_def archObjSize_def pageBits_def
         split: kernel_object.split arch_kernel_object.split)

lemma magnitudeCheck_assert2:
  "\<lbrakk> is_aligned x n; (1 :: word32) < 2 ^ n; ksPSpace s x = Some v \<rbrakk> \<Longrightarrow>
   magnitudeCheck x (snd (lookupAround2 x (ksPSpace (s :: kernel_state)))) n
     = assert (ps_clear x n s)"
  using in_magnitude_check[where x=x and n=n and s=s and s'=s and v="()"]
  by (simp add: magnitudeCheck_assert in_monad)

lemma getObject_get_assert:
  assumes deflt: "\<And>a b c d. (loadObject a b c d :: ('a :: pspace_storable) kernel)
                          = loadObject_default a b c d"
  shows
  "(getObject p :: ('a :: pspace_storable) kernel)
   = do v \<leftarrow> gets (obj_at' (\<lambda>x :: 'a. True) p);
        assert v;
        gets (the o projectKO_opt o the o swp fun_app p o ksPSpace)
     od"
  apply (rule ext)
  apply (simp add: exec_get getObject_def split_def exec_gets
                   deflt loadObject_default_def projectKO_def2
                   alignCheck_assert)
  apply (case_tac "ksPSpace x p")
   apply (simp add: obj_at'_def assert_opt_def assert_def
             split: option.split split_if)
  apply (simp add: lookupAround2_known1 assert_opt_def
                   obj_at'_def projectKO_def2
            split: option.split)
  apply (clarsimp simp: fail_def fst_return conj_comms project_inject
                        objBits_def)
  apply (simp only: assert2[symmetric],
         rule bind_apply_cong[OF refl])
  apply (clarsimp simp: in_monad)
  apply (fold objBits_def)
  apply (simp add: magnitudeCheck_assert2[OF _ objBits_2n])
  apply (rule bind_apply_cong[OF refl])
  apply (clarsimp simp: in_monad return_def simpler_gets_def)
  apply (simp add: iffD2[OF project_inject refl])
  done

lemma obj_at_partial_overwrite_If:
  "\<lbrakk> \<forall>x. tcb_at' (idx x) s \<rbrakk>
    \<Longrightarrow> obj_at' P p (ksPSpace_update (partial_overwrite idx f) s)
             = (if p \<in> range idx
                then obj_at' (\<lambda>tcb. P (put_tcb_state_regs_tcb (f (inv idx p)) tcb)) p s
                else obj_at' P p s)"
  apply (frule dom_partial_overwrite[where tsrs=f])
  apply (simp add: obj_at'_def ps_clear_def partial_overwrite_def
                   projectKOs split: split_if)
  apply clarsimp
  apply (drule_tac x=x in spec)
  apply (clarsimp simp: put_tcb_state_regs_def objBits_simps)
  done

lemma obj_at_partial_overwrite_id1:
  "\<lbrakk> p \<notin> range idx; \<forall>x. tcb_at' (idx x) s \<rbrakk>
    \<Longrightarrow> obj_at' P p (ksPSpace_update (partial_overwrite idx f) s)
             = obj_at' P p s"
  apply (drule dom_partial_overwrite[where tsrs=f])
  apply (simp add: obj_at'_def ps_clear_def partial_overwrite_def
                   projectKOs)
  done

lemma obj_at_partial_overwrite_id2:
  "\<lbrakk> \<forall>x. tcb_at' (idx x) s; \<And>v tcb. P v \<or> True \<Longrightarrow> injectKO v \<noteq> KOTCB tcb \<rbrakk>
    \<Longrightarrow> obj_at' P p (ksPSpace_update (partial_overwrite idx f) s)
             = obj_at' P p s"
  apply (frule dom_partial_overwrite[where tsrs=f])
  apply (simp add: obj_at'_def ps_clear_def partial_overwrite_def
                   projectKOs split: split_if)
  apply clarsimp
  apply (drule_tac x=x in spec)
  apply (clarsimp simp: put_tcb_state_regs_def objBits_simps
                        project_inject)
  done

lemma getObject_isolatable:
  "\<lbrakk> \<And>a b c d. (loadObject a b c d :: 'a kernel) = loadObject_default a b c d;
      \<And>tcb. projectKO_opt (KOTCB tcb) = (None :: 'a option) \<rbrakk> \<Longrightarrow>
   thread_actions_isolatable idx (getObject p :: ('a :: pspace_storable) kernel)"
  apply (clarsimp simp: thread_actions_isolatable_def)
  apply (simp add: getObject_get_assert split_def
                   isolate_thread_actions_def bind_select_f_bind[symmetric]
                   bind_assoc select_f_asserts select_f_returns)
  apply (clarsimp simp: monadic_rewrite_def exec_gets getSchedulerAction_def)
  apply (case_tac "p \<in> range idx")
   apply clarsimp
   apply (drule_tac x=x in spec)
   apply (clarsimp simp: obj_at'_def projectKOs partial_overwrite_def
                         put_tcb_state_regs_def)
  apply (simp add: obj_at_partial_overwrite_id1)
  apply (simp add: partial_overwrite_def)
  apply (rule bind_apply_cong[OF refl])
  apply (simp add: exec_modify return_def o_def simpler_gets_def
                   ksPSpace_update_partial_id in_monad)
  done

lemma gets_isolatable:
  "\<lbrakk> \<And>g h s. \<forall>x. tcb_at' (idx x) s \<Longrightarrow>
        f (ksSchedulerAction_update g
             (ksPSpace_update (partial_overwrite idx (\<lambda>_. undefined)) s)) = f s \<rbrakk> \<Longrightarrow>
   thread_actions_isolatable idx (gets f)"
  apply (clarsimp simp: thread_actions_isolatable_def)
  apply (simp add: isolate_thread_actions_def select_f_returns
                   liftM_def bind_assoc)
  apply (clarsimp simp: monadic_rewrite_def exec_gets
                   getSchedulerAction_def exec_modify)
  apply (simp add: simpler_gets_def return_def
                   ksPSpace_update_partial_id o_def)
  done

lemma modify_isolatable:
  assumes swap:"\<And>tsrs act s. \<forall>x. tcb_at' (idx x) s \<Longrightarrow>
            (ksPSpace_update (partial_overwrite idx tsrs) ((f s)\<lparr> ksSchedulerAction := act \<rparr>))
                = f (ksPSpace_update (partial_overwrite idx tsrs)
                      (s \<lparr> ksSchedulerAction := act\<rparr>))"
  shows
     "thread_actions_isolatable idx (modify f)"
  apply (clarsimp simp: thread_actions_isolatable_def)
  apply (simp add: isolate_thread_actions_def select_f_returns
                   liftM_def bind_assoc)
  apply (clarsimp simp: monadic_rewrite_def exec_gets
                   getSchedulerAction_def)
  apply (simp add: simpler_modify_def o_def)
  apply (subst swap)
   apply (simp add: obj_at_partial_overwrite_If)
  apply (simp add: ksPSpace_update_partial_id o_def)
  done

lemma isolate_thread_actions_wrap_bind:
  "inj idx \<Longrightarrow>
   do x \<leftarrow> isolate_thread_actions idx a b c;
      isolate_thread_actions idx (d x) e f
   od =
   isolate_thread_actions idx
             (do x \<leftarrow> isolate_thread_actions idx a id id;
                 isolate_thread_actions idx (d x) id id
                od) (e o b) (f o c)
   "
  apply (rule ext)
  apply (clarsimp simp: isolate_thread_actions_def bind_assoc split_def
                        bind_select_f_bind[symmetric] liftM_def
                        select_f_returns select_f_selects
                        getSchedulerAction_def)
  apply (clarsimp simp: exec_gets getSchedulerAction_def o_def)
  apply (rule select_bind_eq)
  apply (simp add: exec_gets exec_modify o_def)
  apply (rule select_bind_eq)
  apply (simp add: exec_modify)
  done

lemma monadic_rewrite_in_isolate_thread_actions:
  "\<lbrakk> inj idx; monadic_rewrite F True P a d \<rbrakk> \<Longrightarrow>
   monadic_rewrite F True (\<lambda>s. P (ksSchedulerAction_update (\<lambda>_. ResumeCurrentThread)
                            (ksPSpace_update (partial_overwrite idx (\<lambda>_. undefined)) s)))
     (isolate_thread_actions idx a b c) (isolate_thread_actions idx d b c)"
  apply (clarsimp simp: isolate_thread_actions_def split_def)
  apply (rule monadic_rewrite_bind_tail)+
     apply (rule_tac P="\<lambda>_. P s" in monadic_rewrite_bind_head)
     apply (simp add: monadic_rewrite_def select_f_def)
    apply wp
  apply simp
  done

lemma thread_actions_isolatable_bind:
  "\<lbrakk> thread_actions_isolatable idx f; \<And>x. thread_actions_isolatable idx (g x);
       \<And>t. \<lbrace>tcb_at' t\<rbrace> f \<lbrace>\<lambda>rv. tcb_at' t\<rbrace> \<rbrakk>
     \<Longrightarrow> thread_actions_isolatable idx (f >>= g)"
  apply (clarsimp simp: thread_actions_isolatable_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (erule monadic_rewrite_bind2, assumption)
    apply (rule hoare_vcg_all_lift, assumption)
   apply (subst isolate_thread_actions_wrap_bind, simp)
   apply simp
   apply (rule monadic_rewrite_in_isolate_thread_actions, assumption)
   apply (rule monadic_rewrite_transverse)
    apply (erule monadic_rewrite_bind2, assumption)
    apply (rule hoare_vcg_all_lift, assumption)
   apply (simp add: bind_assoc id_def)
   apply (rule monadic_rewrite_refl)
  apply (simp add: obj_at_partial_overwrite_If)
  done

lemma thread_actions_isolatable_return:
  "thread_actions_isolatable idx (return v)"
  apply (clarsimp simp: thread_actions_isolatable_def
                        monadic_rewrite_def liftM_def
                        isolate_thread_actions_def
                        split_def bind_assoc select_f_returns
                        exec_gets getSchedulerAction_def)
  apply (simp add: exec_modify return_def o_def
                   ksPSpace_update_partial_id)
  done

lemma thread_actions_isolatable_fail:
  "thread_actions_isolatable idx fail"
  by (simp add: thread_actions_isolatable_def
                isolate_thread_actions_def select_f_asserts
                liftM_def bind_assoc getSchedulerAction_def
                monadic_rewrite_def exec_gets)

lemma thread_actions_isolatable_returns:
  "thread_actions_isolatable idx (return v)"
  "thread_actions_isolatable idx (returnOk v)"
  "thread_actions_isolatable idx (throwError v)"
  by (simp add: returnOk_def throwError_def
                thread_actions_isolatable_return)+

lemma thread_actions_isolatable_bindE:
  "\<lbrakk> thread_actions_isolatable idx f; \<And>x. thread_actions_isolatable idx (g x);
       \<And>t. \<lbrace>tcb_at' t\<rbrace> f \<lbrace>\<lambda>rv. tcb_at' t\<rbrace> \<rbrakk>
     \<Longrightarrow> thread_actions_isolatable idx (f >>=E g)"
  apply (simp add: bindE_def)
  apply (erule thread_actions_isolatable_bind)
   apply (simp add: lift_def thread_actions_isolatable_returns
             split: sum.split)
  apply assumption
  done

lemma thread_actions_isolatable_catch:
  "\<lbrakk> thread_actions_isolatable idx f; \<And>x. thread_actions_isolatable idx (g x);
       \<And>t. \<lbrace>tcb_at' t\<rbrace> f \<lbrace>\<lambda>rv. tcb_at' t\<rbrace> \<rbrakk>
     \<Longrightarrow> thread_actions_isolatable idx (f <catch> g)"
  apply (simp add: catch_def)
  apply (erule thread_actions_isolatable_bind)
   apply (simp add: thread_actions_isolatable_returns
             split: sum.split)
  apply assumption
  done

lemma thread_actions_isolatable_if:
  "\<lbrakk> P \<Longrightarrow> thread_actions_isolatable idx a;
     \<not> P \<Longrightarrow> thread_actions_isolatable idx b \<rbrakk>
      \<Longrightarrow> thread_actions_isolatable idx (if P then a else b)"
  by (cases P, simp_all)

lemma select_f_isolatable:
  "thread_actions_isolatable idx (select_f v)"
  apply (clarsimp simp: thread_actions_isolatable_def
                        isolate_thread_actions_def
                        split_def select_f_selects liftM_def bind_assoc)
  apply (rule monadic_rewrite_imp, rule monadic_rewrite_transverse)
    apply (rule monadic_rewrite_drop_modify monadic_rewrite_bind_tail)+
       apply wp
   apply (simp add: gets_bind_ign getSchedulerAction_def)
   apply (rule monadic_rewrite_refl)
  apply (simp add: ksPSpace_update_partial_id o_def)
  done

lemma doMachineOp_isolatable:
  "thread_actions_isolatable idx (doMachineOp m)"
  apply (simp add: doMachineOp_def split_def)
  apply (intro thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               gets_isolatable thread_actions_isolatable_returns
               modify_isolatable select_f_isolatable)
  apply (simp | wp)+
  done

lemma page_directory_at_partial_overwrite:
  "\<forall>x. tcb_at' (idx x) s \<Longrightarrow>
   page_directory_at' p (ksPSpace_update (partial_overwrite idx f) s)
      = page_directory_at' p s"
  by (simp add: page_directory_at'_def typ_at_to_obj_at_arches
                obj_at_partial_overwrite_id2)

lemma findPDForASID_isolatable:
  "thread_actions_isolatable idx (findPDForASID asid)"
  apply (simp add: findPDForASID_def liftE_bindE liftME_def bindE_assoc
                   case_option_If2 assertE_def liftE_def checkPDAt_def
                   stateAssert_def2
             cong: if_cong)
  apply (intro thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_bindE[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_if thread_actions_isolatable_returns
               thread_actions_isolatable_fail
               gets_isolatable getObject_isolatable)
    apply (simp add: projectKO_opt_asidpool page_directory_at_partial_overwrite
           | wp getASID_wp)+
  done

lemma getHWASID_isolatable:
  "thread_actions_isolatable idx (getHWASID asid)"
  apply (simp add: getHWASID_def loadHWASID_def
                   findFreeHWASID_def
                   case_option_If2 findPDForASIDAssert_def
                   checkPDAt_def checkPDUniqueToASID_def
                   checkPDASIDMapMembership_def
                   stateAssert_def2 const_def assert_def
                   findFreeHWASID_def
                   invalidateASID_def
                   invalidateHWASIDEntry_def
                   storeHWASID_def
             cong: if_cong)
  apply (intro thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_bindE[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_catch[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_if thread_actions_isolatable_returns
               thread_actions_isolatable_fail
               gets_isolatable modify_isolatable
               findPDForASID_isolatable doMachineOp_isolatable)
  apply (wp hoare_drop_imps
            | simp add: page_directory_at_partial_overwrite)+
  done

lemma setVMRoot_isolatable:
  "thread_actions_isolatable idx (setVMRoot t)"
  apply (simp add: setVMRoot_def getThreadVSpaceRoot_def
                   locateSlot_conv getSlotCap_def
                   cap_case_isPageDirectoryCap if_bool_simps
                   whenE_def liftE_def 
                   checkPDNotInASIDMap_def stateAssert_def2
                   checkPDASIDMapMembership_def armv_contextSwitch_def
             cong: if_cong)
  apply (intro thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_bindE[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_catch[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_if thread_actions_isolatable_returns
               thread_actions_isolatable_fail
               gets_isolatable getCTE_isolatable getHWASID_isolatable
               findPDForASID_isolatable doMachineOp_isolatable)
    apply (simp add: projectKO_opt_asidpool
           | wp getASID_wp typ_at_lifts [OF getHWASID_typ_at'])+
  done

lemma transferCaps_simple:
  "transferCaps mi [] ep receiver rcvrBuf diminish =
        do
          getReceiveSlots receiver rcvrBuf;
          return (mi\<lparr>msgExtraCaps := 0, msgCapsUnwrapped := 0\<rparr>)
        od"
  apply (cases mi)
  apply (clarsimp simp: transferCaps_def getThreadCSpaceRoot_def locateSlot_conv)
  apply (rule ext bind_apply_cong[OF refl])+
  apply (simp add: upto_enum_def
            split: option.split)
  done

lemma transferCaps_simple_rewrite:
  "monadic_rewrite True True ((\<lambda>_. caps = []) and \<top>)
   (transferCaps mi caps ep r rBuf diminish)
   (return (mi \<lparr> msgExtraCaps := 0, msgCapsUnwrapped := 0 \<rparr>))"
  apply (rule monadic_rewrite_gen_asm)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (simp add: transferCaps_simple, rule monadic_rewrite_refl)
   apply (rule monadic_rewrite_symb_exec2, wp empty_fail_getReceiveSlots)
   apply (rule monadic_rewrite_refl)
  apply simp
  done

lemma lookupExtraCaps_simple_rewrite:
  "msgExtraCaps mi = 0 \<Longrightarrow>
      (lookupExtraCaps thread rcvBuf mi = returnOk [])"
  by (cases mi, simp add: lookupExtraCaps_def getExtraCPtrs_def
                          liftE_bindE upto_enum_step_def mapM_Nil
                   split: option.split)

lemma doIPCTransfer_simple_rewrite:
  "monadic_rewrite True True
   ((\<lambda>_. msgExtraCaps (messageInfoFromWord msgInfo) = 0
               \<and> msgLength (messageInfoFromWord msgInfo)
                      \<le> of_nat (length State_H.msgRegisters))
      and obj_at' (\<lambda>tcb. tcbFault tcb = None
               \<and> tcbContext tcb msgInfoRegister = msgInfo) sender)
   (doIPCTransfer sender ep badge True rcvr diminish)
   (do rv \<leftarrow> mapM_x (\<lambda>r. do v \<leftarrow> asUser sender (getRegister r);
                             asUser rcvr (setRegister r v)
                          od)
               (take (unat (msgLength (messageInfoFromWord msgInfo))) State_H.msgRegisters);
         y \<leftarrow> setMessageInfo rcvr ((messageInfoFromWord msgInfo) \<lparr>msgCapsUnwrapped := 0\<rparr>);
         asUser rcvr (setRegister State_H.badgeRegister badge)
      od)"
  apply (rule monadic_rewrite_gen_asm)
  apply (simp add: doIPCTransfer_def bind_assoc doNormalTransfer_def
                   getMessageInfo_def
             cong: option.case_cong)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)+
      apply (rule_tac P="fault = None" in monadic_rewrite_gen_asm, simp)
      apply (rule monadic_rewrite_bind_tail)
       apply (rule_tac x=msgInfo in monadic_rewrite_symb_exec,
              wp empty_fail_user_getreg user_getreg_rv)
       apply (simp add: lookupExtraCaps_simple_rewrite returnOk_catch_bind)
       apply (rule monadic_rewrite_bind)
         apply (rule monadic_rewrite_from_simple, rule copyMRs_simple)
        apply (rule monadic_rewrite_bind_head)
        apply (rule transferCaps_simple_rewrite)
       apply (wp threadGet_const)
   apply (simp add: bind_assoc)
   apply (rule monadic_rewrite_symb_exec2[OF lookupIPC_inv empty_fail_lookupIPCBuffer]
               monadic_rewrite_symb_exec2[OF threadGet_inv empty_fail_threadGet]
               monadic_rewrite_symb_exec2[OF user_getreg_inv' empty_fail_user_getreg]
               monadic_rewrite_bind_head monadic_rewrite_bind_tail
                  | wp)+
    apply (case_tac "messageInfoFromWord msgInfo")
    apply simp
    apply (rule monadic_rewrite_refl)
   apply wp
  apply clarsimp
  apply (auto elim!: obj_at'_weakenE)
  done

lemma monadic_rewrite_setSchedulerAction_noop:
  "monadic_rewrite F E (\<lambda>s. ksSchedulerAction s = act) (setSchedulerAction act) (return ())"
  unfolding setSchedulerAction_def
  apply (rule monadic_rewrite_imp, rule monadic_rewrite_modify_noop)
  apply simp
  done

lemma rescheduleRequired_simple_rewrite:
  "monadic_rewrite F E
     (sch_act_simple)
     rescheduleRequired
     (setSchedulerAction ChooseNewThread)"
  apply (simp add: rescheduleRequired_def getSchedulerAction_def)
  apply (simp add: monadic_rewrite_def exec_gets sch_act_simple_def)
  apply auto
  done

lemma setThreadState_blocked_rewrite:
  "\<not> runnable' st \<Longrightarrow>
   monadic_rewrite True True
     (\<lambda>s. ksCurThread s = t \<and> ksSchedulerAction s \<noteq> ResumeCurrentThread \<and> tcb_at' t s)
     (setThreadState st t)
     (threadSet (tcbState_update (\<lambda>_. st)) t)"
  apply (simp add: setThreadState_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_trans)
      apply (rule monadic_rewrite_bind_tail)+
         apply (rule_tac P="\<not> runnable \<and> curThread = t
                              \<and> (action \<noteq> ResumeCurrentThread)"
                    in monadic_rewrite_gen_asm)
         apply (simp add: when_def)
         apply (rule monadic_rewrite_refl)
        apply wp
     apply (rule monadic_rewrite_symb_exec2,
            (wp  empty_fail_isRunnable
               | (simp only: getCurThread_def getSchedulerAction_def
                      , rule empty_fail_gets))+)+
     apply (rule monadic_rewrite_refl)
    apply (simp add: conj_comms, wp)
    apply (rule_tac Q="\<lambda>rv s. obj_at' (Not o runnable' o tcbState) t s"
               in hoare_post_imp)
     apply (clarsimp simp: obj_at'_def sch_act_simple_def st_tcb_at'_def)
    apply (wp)
   apply simp
   apply (rule monadic_rewrite_refl)
  apply clarsimp
  done

lemma setupCallerCap_rewrite:
  "monadic_rewrite True True (\<lambda>s. reply_masters_rvk_fb (ctes_of s))
   (setupCallerCap send rcv)
   (do setThreadState BlockedOnReply send;
       replySlot \<leftarrow> getThreadReplySlot send;
       callerSlot \<leftarrow> getThreadCallerSlot rcv;
       replySlotCTE \<leftarrow> getCTE replySlot;
       assert (mdbNext (cteMDBNode replySlotCTE) = 0
                 \<and> isReplyCap (cteCap replySlotCTE)
                 \<and> capReplyMaster (cteCap replySlotCTE)
                 \<and> mdbFirstBadged (cteMDBNode replySlotCTE)
                 \<and> mdbRevocable (cteMDBNode replySlotCTE));
       cteInsert (ReplyCap send False) replySlot callerSlot
    od)"
  apply (simp add: setupCallerCap_def getThreadCallerSlot_def
                   getThreadReplySlot_def locateSlot_conv
                   getSlotCap_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_bind_tail)+
     apply (rule monadic_rewrite_assert)+
     apply (rule_tac P="mdbFirstBadged (cteMDBNode masterCTE)
                        \<and> mdbRevocable (cteMDBNode masterCTE)"
                 in monadic_rewrite_gen_asm)
     apply simp
     apply (rule monadic_rewrite_trans)
      apply (rule monadic_rewrite_bind_tail)
       apply (rule monadic_rewrite_symb_exec2, (wp | simp)+)+
       apply (rule monadic_rewrite_refl)
      apply wp
     apply (rule monadic_rewrite_symb_exec2, wp empty_fail_getCTE)+
     apply (rule monadic_rewrite_refl)
    apply (wp getCTE_wp' | simp add: cte_wp_at_ctes_of)+
  apply (clarsimp simp: reply_masters_rvk_fb_def)
  apply fastforce
  done

lemma attemptSwitchTo_rewrite:
  "monadic_rewrite True True
          (\<lambda>s. obj_at' (\<lambda>tcb. tcbPriority tcb = curPrio) thread s
              \<and> obj_at' (\<lambda>tcb. tcbPriority tcb = destPrio \<and> tcbDomain tcb = destDom) t s
              \<and> destPrio \<ge> curPrio
              \<and> ksSchedulerAction s = ResumeCurrentThread
              \<and> ksCurThread s = thread
              \<and> ksCurDomain s = curDom
              \<and> destDom = curDom)
    (attemptSwitchTo t) (setSchedulerAction (SwitchToThread t))"
  apply (simp add: attemptSwitchTo_def possibleSwitchTo_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_bind_tail)
      apply (rule monadic_rewrite_bind_tail)
       apply (rule monadic_rewrite_bind_tail)
        apply (rule monadic_rewrite_bind_tail)
         apply (rule monadic_rewrite_bind_tail)
          apply (rule_tac P="curPrio \<le> targetPrio \<and> action = ResumeCurrentThread
                                \<and> targetDom = curDom"
                    in monadic_rewrite_gen_asm)
          apply (simp add: eq_commute le_less[symmetric])
          apply (rule monadic_rewrite_refl)
         apply (wp threadGet_wp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_symb_exec2,
            wp empty_fail_threadGet | simp add: getSchedulerAction_def curDomain_def)+
     apply (rule monadic_rewrite_refl)
    apply wp
   apply (rule monadic_rewrite_symb_exec2, simp_all add: getCurThread_def)
   apply (rule monadic_rewrite_refl)
  apply (auto simp: obj_at'_def)
  done

lemma oblivious_getObject_ksPSpace_default:
  "\<lbrakk> \<forall>s. ksPSpace (f s) = ksPSpace s;
      \<And>a b c ko. (loadObject a b c ko :: 'a kernel) \<equiv> loadObject_default a b c ko \<rbrakk> \<Longrightarrow>
   oblivious f (getObject p :: ('a :: pspace_storable) kernel)"
  apply (simp add: getObject_def split_def loadObject_default_def
                   projectKO_def2 alignCheck_assert magnitudeCheck_assert)
  apply (intro oblivious_bind, simp_all)
  done

lemmas oblivious_getObject_ksPSpace_tcb[simp]
    = oblivious_getObject_ksPSpace_default[OF _ loadObject_tcb]

lemma oblivious_setObject_ksPSpace_tcb[simp]:
  "\<lbrakk> \<forall>s. ksPSpace (f s) = ksPSpace s;
     \<forall>s g. ksPSpace_update g (f s) = f (ksPSpace_update g s) \<rbrakk> \<Longrightarrow>
   oblivious f (setObject p (v :: tcb))"
  apply (simp add: setObject_def split_def updateObject_default_def
                   projectKO_def2 alignCheck_assert magnitudeCheck_assert)
  apply (intro oblivious_bind, simp_all)
  done

lemma oblivious_getObject_ksPSpace_cte[simp]:
  "\<lbrakk> \<forall>s. ksPSpace (f s) = ksPSpace s \<rbrakk> \<Longrightarrow>
   oblivious f (getObject p :: cte kernel)"
  apply (simp add: getObject_def split_def loadObject_cte
                   projectKO_def2 alignCheck_assert magnitudeCheck_assert
                   typeError_def unless_when
             cong: Structures_H.kernel_object.case_cong)
  apply (intro oblivious_bind,
         simp_all split: Structures_H.kernel_object.split split_if)
  apply (safe intro!: oblivious_bind, simp_all)
  done

lemma oblivious_doMachineOp[simp]:
  "\<lbrakk> \<forall>s. ksMachineState (f s) = ksMachineState s;
     \<forall>g s. ksMachineState_update g (f s) = f (ksMachineState_update g s) \<rbrakk>
      \<Longrightarrow> oblivious f (doMachineOp oper)"
  apply (simp add: doMachineOp_def split_def)
  apply (intro oblivious_bind, simp_all)
  done

lemmas oblivious_getObject_ksPSpace_asidpool[simp]
    = oblivious_getObject_ksPSpace_default[OF _ loadObject_asidpool]

lemma oblivious_setVMRoot_schact:
  "oblivious (ksSchedulerAction_update f) (setVMRoot t)"
  apply (simp add: setVMRoot_def getThreadVSpaceRoot_def locateSlot_conv
                   getSlotCap_def getCTE_def armv_contextSwitch_def)
  apply (safe intro!: oblivious_bind oblivious_bindE oblivious_catch
             | simp_all add: liftE_def getHWASID_def
                             findPDForASID_def liftME_def loadHWASID_def
                             findPDForASIDAssert_def checkPDAt_def
                             checkPDUniqueToASID_def
                             checkPDASIDMapMembership_def
                             findFreeHWASID_def invalidateASID_def
                             invalidateHWASIDEntry_def storeHWASID_def
                             checkPDNotInASIDMap_def armv_contextSwitch_def
                      split: capability.split arch_capability.split option.split)+
  done

lemma oblivious_switchToThread_schact:
  "oblivious (ksSchedulerAction_update f) (ThreadDecls_H.switchToThread t)"
  apply (simp add: switchToThread_def ArchThread_H.switchToThread_def bind_assoc
                   getCurThread_def setCurThread_def threadGet_def liftM_def
                   threadSet_def tcbSchedEnqueue_def unless_when
                   getQueue_def setQueue_def storeWordUser_def
                   pointerInUserData_def isRunnable_def isBlocked_def
                   getThreadState_def tcbSchedDequeue_def)
  apply (safe intro!: oblivious_bind
              | simp_all add: oblivious_setVMRoot_schact)+
  done

lemma schedule_rewrite:
  notes hoare_TrueI[simp]
  shows "monadic_rewrite True True
            (\<lambda>s. ksSchedulerAction s = SwitchToThread t \<and> ct_in_state' (op = Running) s)
            (schedule)
            (do curThread \<leftarrow> getCurThread; tcbSchedEnqueue curThread; setSchedulerAction ResumeCurrentThread; switchToThread t od)"
  apply (simp add: schedule_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_bind_tail)
      apply (rule_tac P="action = SwitchToThread t" in monadic_rewrite_gen_asm, simp)
      apply (rule monadic_rewrite_bind_tail)
       apply (rule_tac P="curRunnable \<and> action = SwitchToThread t" in monadic_rewrite_gen_asm, simp)
       apply (rule monadic_rewrite_refl)
      apply (wp,simp,wp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_symb_exec2, wp | simp add: isRunnable_def getSchedulerAction_def)+
     apply (rule monadic_rewrite_refl)
    apply (wp)
   apply (simp add: setSchedulerAction_def)
   apply (subst oblivious_modify_swap[symmetric], rule oblivious_switchToThread_schact)
   apply (rule monadic_rewrite_refl)
  apply (clarsimp simp: st_tcb_at'_def pred_neg_def o_def obj_at'_def ct_in_state'_def)
  done

lemma schedule_rewrite_ct_not_runnable':
  "monadic_rewrite True True
            (\<lambda>s. ksSchedulerAction s = SwitchToThread t \<and> ct_in_state' (Not \<circ> runnable') s)
            (schedule)
            (do setSchedulerAction ResumeCurrentThread; switchToThread t od)"
  apply (simp add: schedule_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_bind_tail)
      apply (rule_tac P="action = SwitchToThread t" in monadic_rewrite_gen_asm, simp)
      apply (rule monadic_rewrite_bind_tail)
       apply (rule_tac P="\<not> curRunnable \<and> action = SwitchToThread t" in monadic_rewrite_gen_asm,simp)
       apply (rule monadic_rewrite_refl)
      apply (wp,simp,wp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_symb_exec2, wp |
            simp add: isRunnable_def getSchedulerAction_def |
            rule hoare_TrueI)+
     apply (rule monadic_rewrite_refl)
    apply (wp)
   apply (simp add: setSchedulerAction_def)
   apply (subst oblivious_modify_swap[symmetric], rule oblivious_switchToThread_schact)
   apply (rule monadic_rewrite_symb_exec2)
   apply (wp, simp, rule hoare_TrueI)
   apply (rule monadic_rewrite_refl)
  apply (clarsimp simp: st_tcb_at'_def pred_neg_def o_def obj_at'_def ct_in_state'_def)
  done

lemma activateThread_simple_rewrite:
  "monadic_rewrite True True (ct_in_state' (op = Running))
       (activateThread) (return ())"
  apply (simp add: activateThread_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans, rule monadic_rewrite_bind_tail)+
       apply (rule_tac P="state = Running" in monadic_rewrite_gen_asm)
       apply simp
       apply (rule monadic_rewrite_refl)
      apply wp
     apply (rule monadic_rewrite_symb_exec2, wp empty_fail_getThreadState)
     apply (rule monadic_rewrite_refl)
    apply wp
   apply (rule monadic_rewrite_symb_exec2,
          simp_all add: getCurThread_def)
   apply (rule monadic_rewrite_refl)
  apply (clarsimp simp: ct_in_state'_def elim!: st_tcb'_weakenE)
  done

end

lemma setCTE_obj_at_prio[wp]:
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbPriority tcb)) t\<rbrace> setCTE p v \<lbrace>\<lambda>rv. obj_at' (\<lambda>tcb. P (tcbPriority tcb)) t\<rbrace>"
  unfolding setCTE_def
  by (rule setObject_cte_obj_at_tcb', simp+)

crunch obj_at_prio[wp]: cteInsert "obj_at' (\<lambda>tcb. P (tcbPriority tcb)) t"
  (wp: crunch_wps)

crunch ctes_of[wp]: asUser "\<lambda>s. P (ctes_of s)"
  (wp: crunch_wps)

lemma tcbSchedEnqueue_tcbPriority[wp]:
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbPriority tcb)) t\<rbrace>
     tcbSchedEnqueue t'
   \<lbrace>\<lambda>rv. obj_at' (\<lambda>tcb. P (tcbPriority tcb)) t\<rbrace>"
  apply (simp add: tcbSchedEnqueue_def unless_def)
  apply (wp | simp cong: if_cong)+
  done

crunch obj_at_prio[wp]: cteDeleteOne "obj_at' (\<lambda>tcb. P (tcbPriority tcb)) t"
  (wp: crunch_wps setEndpoint_obj_at_tcb'
       setThreadState_obj_at_unchanged setAsyncEP_tcb
        simp: crunch_simps unless_def)

context kernel_m begin

lemma setThreadState_no_sch_change:
  "\<lbrace>\<lambda>s. P (ksSchedulerAction s) \<and> (runnable' st \<or> t \<noteq> ksCurThread s)\<rbrace>
      setThreadState st t
   \<lbrace>\<lambda>rv s. P (ksSchedulerAction s)\<rbrace>"
  (is "NonDetMonad.valid ?P ?f ?Q")
  apply (simp add: setThreadState_def setSchedulerAction_def)
  apply (wp hoare_pre_cont[where a=rescheduleRequired])
  apply (rule_tac Q="\<lambda>_. ?P and st_tcb_at' (op = st) t" in hoare_post_imp)
   apply (clarsimp split: split_if)
   apply (clarsimp simp: obj_at'_def st_tcb_at'_def projectKOs)
  apply (rule hoare_pre, wp threadSet_st_tcb_at_state)
  apply simp
  done

lemma asUser_obj_at_unchangedT:
  assumes x: "\<forall>tcb con con'. con' \<in> fst (m con)
        \<longrightarrow> P (tcbContext_update (\<lambda>_. snd con') tcb) = P tcb" shows
  "\<lbrace>obj_at' P t\<rbrace> asUser t' m \<lbrace>\<lambda>rv. obj_at' P t\<rbrace>"
  apply (simp add: asUser_def split_def)
  apply (wp threadSet_obj_at' threadGet_wp)
  apply (clarsimp simp: obj_at'_def projectKOs x cong: if_cong)
  done

lemmas asUser_obj_at_unchanged
    = asUser_obj_at_unchangedT[OF all_tcbI, rule_format]

lemma bind_assoc:
  "do y \<leftarrow> do x \<leftarrow> m; f x od; g y od
     = do x \<leftarrow> m; y \<leftarrow> f x; g y od"
  by (rule bind_assoc)

lemma setObject_modify_assert:
  "\<lbrakk> updateObject v = updateObject_default v \<rbrakk>
    \<Longrightarrow> setObject p v = do f \<leftarrow> gets (obj_at' (\<lambda>v'. v = v' \<or> True) p);
                         assert f; modify (ksPSpace_update (\<lambda>ps. ps(p \<mapsto> injectKO v))) od"
  using objBits_2n[where obj=v]
  apply (simp add: setObject_def split_def updateObject_default_def
                   bind_assoc projectKO_def2 alignCheck_assert)
  apply (rule ext, simp add: exec_gets)
  apply (case_tac "obj_at' (\<lambda>v'. v = v' \<or> True) p x")
   apply (clarsimp simp: obj_at'_def projectKOs lookupAround2_known1
                         assert_opt_def)
   apply (clarsimp simp: project_inject)
   apply (simp only: objBits_def objBitsT_koTypeOf[symmetric] koTypeOf_injectKO)
   apply (simp add: magnitudeCheck_assert2 simpler_modify_def)
  apply (clarsimp simp: assert_opt_def assert_def magnitudeCheck_assert2
                 split: option.split split_if)
  apply (clarsimp simp: obj_at'_def projectKOs)
  apply (clarsimp simp: project_inject)
  apply (simp only: objBits_def objBitsT_koTypeOf[symmetric]
                    koTypeOf_injectKO simp_thms)
  done

lemma setEndpoint_isolatable:
  "thread_actions_isolatable idx (setEndpoint p e)"
  apply (simp add: setEndpoint_def setObject_modify_assert
                   assert_def)
  apply (case_tac "p \<in> range idx")
   apply (clarsimp simp: thread_actions_isolatable_def
                         monadic_rewrite_def fun_eq_iff
                         liftM_def isolate_thread_actions_def
                         bind_assoc exec_gets getSchedulerAction_def
                         bind_select_f_bind[symmetric])
   apply (simp add: obj_at_partial_overwrite_id2)
   apply (drule_tac x=x in spec)
   apply (clarsimp simp: obj_at'_def projectKOs select_f_asserts)
  apply (intro thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_if
               thread_actions_isolatable_return
               thread_actions_isolatable_fail)
       apply (rule gets_isolatable)
       apply (simp add: obj_at_partial_overwrite_id2)
      apply (rule modify_isolatable)
      apply (clarsimp simp: o_def partial_overwrite_def)
      apply (rule kernel_state.fold_congs[OF refl refl])
      apply (clarsimp simp: fun_eq_iff
                     split: split_if)
     apply (wp | simp)+
  done

lemma setCTE_assert_modify:
  "setCTE p v = do c \<leftarrow> gets (real_cte_at' p);
                   t \<leftarrow> gets (tcb_at' (p && ~~ mask 9)
                                 and K ((p && mask 9) \<in> dom tcb_cte_cases));
                   if c then modify (ksPSpace_update (\<lambda>ps. ps(p \<mapsto> KOCTE v)))
                   else if t then
                     modify (ksPSpace_update
                               (\<lambda>ps. ps (p && ~~ mask 9 \<mapsto>
                                           KOTCB (snd (the (tcb_cte_cases (p && mask 9))) (K v)
                                                (the (projectKO_opt (the (ps (p && ~~ mask 9)))))))))
                   else fail od"
  apply (clarsimp simp: setCTE_def setObject_def split_def
                        fun_eq_iff exec_gets)
  apply (case_tac "real_cte_at' p x")
   apply (clarsimp simp: obj_at'_def projectKOs lookupAround2_known1
                         assert_opt_def alignCheck_assert objBits_simps
                         magnitudeCheck_assert2 updateObject_cte)
   apply (simp add: simpler_modify_def)
  apply (simp split: split_if, intro conjI impI)
   apply (clarsimp simp: obj_at'_def projectKOs)
   apply (subgoal_tac "p \<le> (p && ~~ mask 9) + 2 ^ 9 - 1")
    apply (subgoal_tac "fst (lookupAround2 p (ksPSpace x))
                          = Some (p && ~~ mask 9, KOTCB obj)")
     apply (simp add: assert_opt_def)
     apply (subst updateObject_cte_tcb)
      apply (fastforce simp add: subtract_mask)
     apply (simp add: assert_opt_def alignCheck_assert bind_assoc
                      magnitudeCheck_assert
                      is_aligned_neg_mask2 objBits_def)
     apply (rule ps_clear_lookupAround2, assumption+)
       apply (rule word_and_le2)
      apply (simp add: objBits_simps mask_def field_simps)
     apply (simp add: simpler_modify_def cong: option.case_cong if_cong)
     apply (rule kernel_state.fold_congs[OF refl refl])
     apply (clarsimp simp: projectKO_opt_tcb cong: if_cong)
    apply (clarsimp simp: lookupAround2_char1 word_and_le2)
    apply (rule ccontr, clarsimp)
    apply (erule(2) ps_clearD)
    apply (simp add: objBits_simps mask_def field_simps)
   apply (rule tcb_cte_cases_in_range2)
    apply (simp add: subtract_mask)
   apply simp
  apply (clarsimp simp: assert_opt_def split: option.split)
  apply (rule trans [OF bind_apply_cong[OF _ refl] fun_cong[OF fail_bind]])
  apply (simp add: fail_def Pair_fst_snd_eq)
  apply (rule context_conjI)
   apply (rule ccontr, clarsimp elim!: nonemptyE)
   apply (frule(1) updateObject_cte_is_tcb_or_cte[OF _ refl])
   apply (erule disjE)
    apply clarsimp
    apply (frule(1) tcb_cte_cases_aligned_helpers)
    apply (clarsimp simp: domI[where m = cte_cte_cases] field_simps)
    apply (clarsimp simp: lookupAround2_char1 obj_at'_def projectKOs
                          objBits_simps)
   apply (clarsimp simp: obj_at'_def lookupAround2_char1
                         objBits_simps projectKOs cte_level_bits_def)
  apply (erule empty_failD[OF empty_fail_updateObject_cte])
  done

lemma partial_overwrite_fun_upd2:
  "partial_overwrite idx tsrs (f (x := y))
     = (partial_overwrite idx tsrs f)
          (x := if x \<in> range idx then put_tcb_state_regs (tsrs (inv idx x)) y
                else y)"
  by (simp add: fun_eq_iff partial_overwrite_def split: split_if)

lemma setCTE_isolatable:
  "thread_actions_isolatable idx (setCTE p v)"
  apply (simp add: setCTE_assert_modify)
  apply (clarsimp simp: thread_actions_isolatable_def
                        monadic_rewrite_def fun_eq_iff
                        liftM_def exec_gets
                        isolate_thread_actions_def
                        bind_assoc exec_gets getSchedulerAction_def
                        bind_select_f_bind[symmetric]
                        obj_at_partial_overwrite_If
                        obj_at_partial_overwrite_id2
                  cong: if_cong)
  apply (case_tac "p && ~~ mask 9 \<in> range idx \<and> p && mask 9 \<in> dom tcb_cte_cases")
   apply clarsimp
   apply (frule_tac x=x in spec, erule obj_atE')
   apply (subgoal_tac "\<not> real_cte_at' p s")
    apply (clarsimp simp: select_f_returns select_f_asserts split: split_if)
    apply (clarsimp simp: o_def simpler_modify_def partial_overwrite_fun_upd2)
    apply (rule kernel_state.fold_congs[OF refl refl])
    apply (rule ext)
    apply (clarsimp simp: partial_overwrite_get_tcb_state_regs
                   split: split_if)
    apply (clarsimp simp: projectKOs get_tcb_state_regs_def
                          put_tcb_state_regs_def put_tcb_state_regs_tcb_def
                          partial_overwrite_def
                   split: tcb_state_regs.split)
    apply (case_tac obj, simp add: projectKO_opt_tcb)
    apply (simp add: tcb_cte_cases_def split: split_if_asm)
   apply (drule_tac x=x in spec)
   apply (clarsimp simp: obj_at'_def projectKOs objBits_simps subtract_mask(2) [symmetric])
   apply (erule notE[rotated], erule (3) tcb_ctes_clear[rotated])
  apply (simp add: select_f_returns select_f_asserts split: split_if)
  apply (intro conjI impI)
    apply (clarsimp simp: simpler_modify_def fun_eq_iff
                          partial_overwrite_fun_upd2 o_def
                  intro!: kernel_state.fold_congs[OF refl refl])
    apply (clarsimp simp: obj_at'_def projectKOs objBits_simps)
    apply (erule notE[rotated], rule tcb_ctes_clear[rotated 2], assumption+)
     apply (fastforce simp add: subtract_mask)
    apply simp
   apply (clarsimp simp: simpler_modify_def
                         partial_overwrite_fun_upd2 o_def
                         partial_overwrite_get_tcb_state_regs
                 intro!: kernel_state.fold_congs[OF refl refl]
                  split: split_if)
   apply (simp add: partial_overwrite_def)
  apply (subgoal_tac "p \<notin> range idx")
   apply (clarsimp simp: simpler_modify_def
                         partial_overwrite_fun_upd2 o_def
                         partial_overwrite_get_tcb_state_regs
                 intro!: kernel_state.fold_congs[OF refl refl])
  apply clarsimp
  apply (drule_tac x=x in spec)
  apply (clarsimp simp: obj_at'_def projectKOs)
  done

lemma assert_isolatable:
  "thread_actions_isolatable idx (assert P)"
  by (simp add: assert_def thread_actions_isolatable_if
                thread_actions_isolatable_returns
                thread_actions_isolatable_fail)

lemma cteInsert_isolatable:
  "thread_actions_isolatable idx (cteInsert cap src dest)"
  apply (simp add: cteInsert_def updateCap_def updateMDB_def
                   Let_def setUntypedCapAsFull_def)
  apply (intro thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_if
               thread_actions_isolatable_returns assert_isolatable
               getCTE_isolatable setCTE_isolatable)
  apply (wp | simp)+
  done

lemma isolate_thread_actions_threadSet_tcbState:
  "\<lbrakk> inj idx; idx t' = t \<rbrakk> \<Longrightarrow>
   monadic_rewrite False True (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
     (threadSet (tcbState_update (\<lambda>_. st)) t)
     (isolate_thread_actions idx (return ())
         (\<lambda>tsrs. (tsrs (t' := TCBStateRegs st (tsrContext (tsrs t')))))
             id)"
  apply (simp add: isolate_thread_actions_def bind_assoc split_def
                   select_f_returns getSchedulerAction_def)
  apply (clarsimp simp: monadic_rewrite_def exec_gets threadSet_def
                        getObject_get_assert bind_assoc liftM_def
                        setObject_modify_assert)
  apply (frule_tac x=t' in spec, drule obj_at_ko_at')
  apply (clarsimp simp: exec_gets simpler_modify_def o_def
                intro!: kernel_state.fold_congs[OF refl refl])
  apply (simp add: partial_overwrite_fun_upd
                   partial_overwrite_get_tcb_state_regs)
  apply (clarsimp simp: put_tcb_state_regs_def put_tcb_state_regs_tcb_def
                        projectKOs get_tcb_state_regs_def
                 elim!: obj_atE')
  apply (case_tac ko)
  apply (simp add: projectKO_opt_tcb)
  done

lemma thread_actions_isolatableD:
  "\<lbrakk> thread_actions_isolatable idx f; inj idx \<rbrakk>
     \<Longrightarrow> monadic_rewrite False True (\<lambda>s. (\<forall>x. tcb_at' (idx x) s))
            f (isolate_thread_actions idx f id id)"
  by (clarsimp simp: thread_actions_isolatable_def)

lemma tcbSchedDequeue_rewrite:
  "monadic_rewrite True True (obj_at' (Not \<circ> tcbQueued) t) (tcbSchedDequeue t) (return ())"
  apply (simp add: tcbSchedDequeue_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule_tac P="\<not> queued" in monadic_rewrite_gen_asm)
     apply (simp add: when_def)
     apply (rule monadic_rewrite_refl)
    apply (wp threadGet_const)
   apply (rule monadic_rewrite_symb_exec2)
      apply wp
   apply (rule monadic_rewrite_refl)
  apply (clarsimp)
  done

lemma switchToThread_rewrite:
  "monadic_rewrite True True
       (ct_in_state' (Not \<circ> runnable') and cur_tcb' and obj_at' (Not \<circ> tcbQueued) t)
       (switchToThread t)
       (do ArchThreadDecls_H.switchToThread t; setCurThread t od)"
  apply (simp add: switchToThread_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_bind)
     apply (rule tcbSchedDequeue_rewrite)
      apply (rule monadic_rewrite_refl)
     apply (wp Arch_switchToThread_obj_at_pre)
   apply (rule monadic_rewrite_bind_tail)
    apply (rule monadic_rewrite_symb_exec)
       apply (wp, simp)
    apply (rule monadic_rewrite_refl)
   apply (wp)
  apply (clarsimp)
  done

lemma threadGet_isolatable:
  assumes v: "\<And>tsr. \<forall>tcb. f (put_tcb_state_regs_tcb tsr tcb) = f tcb"
  shows "thread_actions_isolatable idx (threadGet f t)"
  apply (clarsimp simp: threadGet_def thread_actions_isolatable_def
                        isolate_thread_actions_def split_def
                        getObject_get_assert liftM_def
                        bind_select_f_bind[symmetric]
                        select_f_returns select_f_asserts bind_assoc)
  apply (clarsimp simp: monadic_rewrite_def exec_gets
                        getSchedulerAction_def)
  apply (simp add: obj_at_partial_overwrite_If)
  apply (rule bind_apply_cong[OF refl])
  apply (clarsimp simp: exec_gets exec_modify o_def
                        ksPSpace_update_partial_id in_monad)
  apply (erule obj_atE')
  apply (clarsimp simp: projectKOs
                        partial_overwrite_def put_tcb_state_regs_def
                  cong: if_cong)
  apply (simp add: projectKO_opt_tcb v split: split_if)
  done

lemma switchToThread_isolatable:
  "thread_actions_isolatable idx (ArchThreadDecls_H.switchToThread t)"
  apply (simp add: ArchThread_H.switchToThread_def
                   storeWordUser_def stateAssert_def2)
  apply (intro thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               gets_isolatable setVMRoot_isolatable
               thread_actions_isolatable_if
               doMachineOp_isolatable
               threadGet_isolatable [OF all_tcbI]
               thread_actions_isolatable_returns
               thread_actions_isolatable_fail)
  apply (wp |
           simp add: pointerInUserData_def
                       typ_at_to_obj_at_arches
                       obj_at_partial_overwrite_id2
                       put_tcb_state_regs_tcb_def
                split: tcb_state_regs.split)+
  done

lemma setCurThread_isolatable:
  "thread_actions_isolatable idx (setCurThread t)"
  by (simp add: setCurThread_def modify_isolatable)

end

crunch tcb2[wp]: "ArchThreadDecls_H.switchToThread" "tcb_at' t"
  (ignore: MachineOps.clearExMonitor)

context kernel_m begin

lemma isolate_thread_actions_tcbs_at:
  assumes f: "\<And>x. \<lbrace>tcb_at' (idx x)\<rbrace> f \<lbrace>\<lambda>rv. tcb_at' (idx x)\<rbrace>" shows
  "\<lbrace>\<lambda>s. \<forall>x. tcb_at' (idx x) s\<rbrace>
       isolate_thread_actions idx f f' f'' \<lbrace>\<lambda>p s. \<forall>x. tcb_at' (idx x) s\<rbrace>"
  apply (simp add: isolate_thread_actions_def split_def)
  apply wp
  apply clarsimp
  apply (simp add: obj_at_partial_overwrite_If use_valid[OF _ f])
  done

lemma isolate_thread_actions_rewrite_bind:
  "\<lbrakk> inj idx; monadic_rewrite False True (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
                  f (isolate_thread_actions idx f' f'' f''');
     \<And>x. monadic_rewrite False True (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
               (g x)
               (isolate_thread_actions idx (g' x) g'' g''');
     thread_actions_isolatable idx f'; \<And>x. thread_actions_isolatable idx (g' x);
     \<And>x. \<lbrace>tcb_at' (idx x)\<rbrace> f' \<lbrace>\<lambda>rv. tcb_at' (idx x)\<rbrace> \<rbrakk>
    \<Longrightarrow> monadic_rewrite False True (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
               (f >>= g) (isolate_thread_actions idx
                                  (f' >>= g') (g'' o f'') (g''' o f'''))"
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind, assumption+)
    apply (wp isolate_thread_actions_tcbs_at)
    apply simp
   apply (subst isolate_thread_actions_wrap_bind, assumption)
   apply (rule monadic_rewrite_in_isolate_thread_actions, assumption)
   apply (rule monadic_rewrite_transverse)
    apply (rule monadic_rewrite_bind2)
      apply (erule(1) thread_actions_isolatableD)
     apply (rule thread_actions_isolatableD, assumption+)
    apply (rule hoare_vcg_all_lift, assumption)
   apply (simp add: liftM_def id_def)
   apply (rule monadic_rewrite_refl)
  apply (simp add: obj_at_partial_overwrite_If)
  done

definition
 "copy_register_tsrs src dest r tsrs
     = tsrs (dest := TCBStateRegs (tsrState (tsrs dest))
                       ((tsrContext (tsrs dest)) (r := tsrContext (tsrs src) r)))"

lemma tcb_at_KOTCB_upd:
  "tcb_at' (idx x) s \<Longrightarrow>
   tcb_at' p (ksPSpace_update (\<lambda>ps. ps(idx x \<mapsto> KOTCB tcb)) s)
        = tcb_at' p s"
  apply (clarsimp simp: obj_at'_def projectKOs objBits_simps
                 split: split_if)
  apply (simp add: ps_clear_def)
  done

lemma copy_register_isolate:
  "\<lbrakk> inj idx; idx x = src; idx y = dest \<rbrakk> \<Longrightarrow>
  monadic_rewrite False True
      (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
           (do v \<leftarrow> asUser src (getRegister r);
                   asUser dest (setRegister r v) od)
           (isolate_thread_actions idx (return ())
                 (copy_register_tsrs x y r) id)"
  apply (simp add: asUser_def split_def bind_assoc
                   getRegister_def setRegister_def
                   select_f_returns isolate_thread_actions_def
                   getSchedulerAction_def)
  apply (simp add: threadGet_def liftM_def getObject_get_assert
                   bind_assoc threadSet_def
                   setObject_modify_assert)
  apply (clarsimp simp: monadic_rewrite_def exec_gets
                        exec_modify tcb_at_KOTCB_upd)
  apply (clarsimp simp: simpler_modify_def
                intro!: kernel_state.fold_congs[OF refl refl])
  apply (clarsimp simp: copy_register_tsrs_def o_def
                        partial_overwrite_fun_upd
                        partial_overwrite_get_tcb_state_regs)
  apply (frule_tac x=x in spec, drule_tac x=y in spec)
  apply (clarsimp simp: obj_at'_def projectKOs objBits_simps
                  cong: if_cong)
  apply (case_tac obj, case_tac obja)
  apply (simp add: projectKO_opt_tcb put_tcb_state_regs_def
                   put_tcb_state_regs_tcb_def get_tcb_state_regs_def
             cong: if_cong)
  apply (auto simp: fun_eq_iff split: split_if)
  done

lemma monadic_rewrite_isolate_final2:
  assumes  mr: "monadic_rewrite F E Q f g"
      and eqs: "\<And>s tsrs. \<lbrakk> P s; tsrs = get_tcb_state_regs o ksPSpace s o idx \<rbrakk>
                      \<Longrightarrow> f' tsrs = g' tsrs"
               "\<And>s. P s \<Longrightarrow> f'' (ksSchedulerAction s) = g'' (ksSchedulerAction s)"
               "\<And>s tsrs sa. R s \<Longrightarrow>
                           Q ((ksPSpace_update (partial_overwrite idx tsrs)
                                      s) (| ksSchedulerAction := sa |))"
  shows
  "monadic_rewrite F E (P and R)
         (isolate_thread_actions idx f f' f'')
         (isolate_thread_actions idx g g' g'')"
  apply (simp add: isolate_thread_actions_def split_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_bind_tail)+
      apply (rule_tac P="\<lambda> s'. Q s" in monadic_rewrite_bind)
        apply (insert mr)[1]
        apply (simp add: monadic_rewrite_def select_f_def)
        apply auto[1]
       apply (rule_tac P="P and (\<lambda>s. tcbs = get_tcb_state_regs o ksPSpace s o idx
                                             \<and> sa = ksSchedulerAction s)"
                    in monadic_rewrite_refl3)
       apply (clarsimp simp: exec_modify eqs return_def)
      apply wp
  apply (clarsimp simp: o_def eqs)
  done

lemmas monadic_rewrite_isolate_final
    = monadic_rewrite_isolate_final2[where R=\<top>, OF monadic_rewrite_refl2, simplified]

lemma copy_registers_isolate:
  "\<lbrakk> inj idx; idx x = t; idx y = t' \<rbrakk> \<Longrightarrow>
   monadic_rewrite False True
      (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
           (mapM_x (\<lambda>r. do v \<leftarrow> asUser t (getRegister r);
                           asUser t' (setRegister r v)
                        od)
             regs)
           (isolate_thread_actions idx
               (return ()) (foldr (copy_register_tsrs x y) (rev regs)) id)"
  apply (induct regs)
   apply (simp add: mapM_x_Nil)
   apply (clarsimp simp: monadic_rewrite_def liftM_def bind_assoc
                         isolate_thread_actions_def
                         split_def exec_gets getSchedulerAction_def
                         select_f_returns o_def ksPSpace_update_partial_id)
   apply (simp add: return_def simpler_modify_def)
  apply (simp add: mapM_x_Cons)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule isolate_thread_actions_rewrite_bind, assumption)
        apply (rule copy_register_isolate, assumption+)
      apply (rule thread_actions_isolatable_returns)+
    apply wp
   apply (rule monadic_rewrite_isolate_final[where P=\<top>], simp+)
  done

lemma setSchedulerAction_isolate:
  "inj idx \<Longrightarrow>
   monadic_rewrite False True (\<lambda>s. \<forall>x. tcb_at' (idx x) s)
        (setSchedulerAction sa)
        (isolate_thread_actions idx (return ()) id (\<lambda>_. sa))"
  apply (clarsimp simp: monadic_rewrite_def liftM_def bind_assoc
                        isolate_thread_actions_def select_f_returns
                        exec_gets getSchedulerAction_def o_def
                        ksPSpace_update_partial_id setSchedulerAction_def)
  apply (simp add: simpler_modify_def)
  done

lemma updateMDB_isolatable:
  "thread_actions_isolatable idx (updateMDB slot f)"
  apply (simp add: updateMDB_def thread_actions_isolatable_return
            split: split_if)
  apply (intro impI thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               getCTE_isolatable setCTE_isolatable,
           (wp | simp)+)
  done

lemma emptySlot_isolatable:
  "thread_actions_isolatable idx (emptySlot slot None)"
  apply (simp add: emptySlot_def updateCap_def
             cong: if_cong)
  apply (intro thread_actions_isolatable_bind[OF _ _ hoare_pre(1)]
               thread_actions_isolatable_if
               getCTE_isolatable setCTE_isolatable
               thread_actions_isolatable_return
               updateMDB_isolatable,
           (wp | simp)+)
  done

lemmas fastpath_isolatables
    = setEndpoint_isolatable getCTE_isolatable
      assert_isolatable cteInsert_isolatable
      switchToThread_isolatable setCurThread_isolatable
      emptySlot_isolatable updateMDB_isolatable
      thread_actions_isolatable_returns

lemmas fastpath_isolate_rewrites
    = isolate_thread_actions_threadSet_tcbState isolate_thread_actions_asUser
      copy_registers_isolate setSchedulerAction_isolate
      fastpath_isolatables[THEN thread_actions_isolatableD]

lemma resolveAddressBits_points_somewhere:
  "\<lbrace>\<lambda>s. \<forall>slot. Q slot s\<rbrace> resolveAddressBits cp cptr bits \<lbrace>Q\<rbrace>,-"
  apply (rule_tac Q'="\<lambda>rv s. \<forall>rv. Q rv s" in hoare_post_imp_R)
   apply wp
  apply clarsimp
  done

lemma user_getregs_wp:
  "\<lbrace>\<lambda>s. tcb_at' t s \<and> (\<forall>tcb. ko_at' tcb t s \<longrightarrow> Q (map (tcbContext tcb) regs) s)\<rbrace>
      asUser t (mapM getRegister regs) \<lbrace>Q\<rbrace>"
  apply (rule hoare_strengthen_post)
   apply (rule hoare_vcg_conj_lift)
    apply (rule asUser_get_registers)
   apply (rule asUser_inv)
   apply (wp mapM_wp' getRegister_inv)
  apply clarsimp
  apply (drule obj_at_ko_at', clarsimp)
  done

lemma foldr_copy_register_tsrs:
  "foldr (copy_register_tsrs x y) rs s
       = (s (y := TCBStateRegs (tsrState (s y))
                       (\<lambda>r. if r \<in> set rs then tsrContext (s x) r
                                 else tsrContext (s y) r)))"
  apply (induct rs)
   apply simp
  apply (simp add: copy_register_tsrs_def fun_eq_iff
            split: split_if)
  done

lemmas cteInsert_obj_at'_not_queued =  cteInsert_obj_at'_queued[of "\<lambda>a. \<not> a"]

lemma fastpath_callKernel_SysCall_corres:
  "monadic_rewrite True False
         (invs' and ct_in_state' (op = Running)
                and (\<lambda>s. ksSchedulerAction s = ResumeCurrentThread))
     (callKernel (SyscallEvent SysCall)) (fastpaths SysCall)"
  apply (rule monadic_rewrite_introduce_alternative)
   apply (simp add: callKernel_def)
  apply (rule monadic_rewrite_imp)
   apply (simp add: handleEvent_def handleCall_def
                    handleInvocation_def liftE_bindE_handle
                    bind_assoc getMessageInfo_def)
   apply (simp add: catch_liftE_bindE unlessE_throw_catch_If
                    unifyFailure_catch_If catch_liftE
                    getMessageInfo_def alternative_bind
                    fastpaths_def
              cong: if_cong)
   apply (rule monadic_rewrite_rdonly_bind_l, wp)
   apply (rule monadic_rewrite_bind_tail)
    apply (rule monadic_rewrite_rdonly_bind_l, wp)
    apply (rule monadic_rewrite_bind_tail)
     apply (rename_tac msgInfo)
     apply (rule monadic_rewrite_rdonly_bind_l, wp)
     apply (rule monadic_rewrite_bind_tail)
      apply (rule monadic_rewrite_symb_exec_r
                     [OF threadGet_inv no_fail_threadGet])
       apply (rename_tac tcbFault)
       apply (rule monadic_rewrite_alternative_rhs[rotated])
        apply (rule monadic_rewrite_alternative_l)
       apply (rule monadic_rewrite_if_rhs[rotated])
        apply (rule monadic_rewrite_alternative_l)
       apply (simp add: split_def Syscall_H.syscall_def
                        liftE_bindE_handle bind_assoc
                        capFaultOnFailure_def)
       apply (simp only: bindE_bind_linearise[where f="rethrowFailure fn f'" for fn f']
                         bind_case_sum_rethrow)
       apply (simp add: lookupCapAndSlot_def lookupSlotForThread_def
                        lookupSlotForThread_def bindE_assoc
                        liftE_bind_return_bindE_returnOk split_def
                        getThreadCSpaceRoot_def locateSlot_conv
                        returnOk_liftE[symmetric] const_def
                        getSlotCap_def)
       apply (simp only: liftE_bindE_assoc)
       apply (rule monadic_rewrite_rdonly_bind_l, wp)
       apply (rule monadic_rewrite_bind_tail)
        apply (rule monadic_rewrite_rdonly_bind_l)
         apply (wp | simp)+
        apply (rule_tac fn="case_sum Inl (Inr \<circ> fst)" in monadic_rewrite_split_fn)
          apply (simp add: liftME_liftM[symmetric] liftME_def bindE_assoc)
          apply (rule monadic_rewrite_refl)
         apply (rule monadic_rewrite_if_rhs[rotated])
          apply (rule monadic_rewrite_alternative_l)
         apply (simp add: isRight_right_map isRight_case_sum)
         apply (rule monadic_rewrite_if_rhs[rotated])
          apply (rule monadic_rewrite_alternative_l)
         apply (rule monadic_rewrite_rdonly_bind_l[OF lookupIPC_inv])
         apply (rule monadic_rewrite_symb_exec_l[OF lookupIPC_inv empty_fail_lookupIPCBuffer])
          apply (simp add: lookupExtraCaps_null returnOk_bind liftE_bindE_handle
                           bind_assoc liftE_bindE_assoc
                           decodeInvocation_def Let_def from_bool_0
                           performInvocation_def liftE_handle
                           liftE_bind)
          apply (rule monadic_rewrite_symb_exec_r [OF getEndpoint_inv no_fail_getEndpoint])
           apply (rename_tac "send_ep")
           apply (rule monadic_rewrite_if_rhs[rotated])
            apply (rule monadic_rewrite_alternative_l)
           apply (simp add: getThreadVSpaceRoot_def locateSlot_conv)
           apply (rule monadic_rewrite_symb_exec_r [OF getCTE_inv no_fail_getCTE])
            apply (rename_tac "pdCapCTE")
            apply (rule monadic_rewrite_if_rhs[rotated])
             apply (rule monadic_rewrite_alternative_l)
            apply (rule monadic_rewrite_symb_exec_r [OF threadGet_inv no_fail_threadGet])+
              apply (rename_tac "curPrio" "destPrio")
              apply (rule monadic_rewrite_if_rhs[rotated])
               apply (rule monadic_rewrite_alternative_l)
              apply (rule monadic_rewrite_if_rhs[rotated])
               apply (rule monadic_rewrite_alternative_l)
              apply (simp add: isRight_case_sum)
              apply (rule monadic_rewrite_symb_exec_r [OF gts_inv' no_fail_getThreadState])
               apply (rename_tac "destState")
               apply (rule monadic_rewrite_if_rhs[rotated])
                apply (rule monadic_rewrite_alternative_l)
               apply (rule monadic_rewrite_symb_exec_r [OF gets_inv non_fail_gets])
                apply (rule monadic_rewrite_if_rhs[rotated])
                 apply (rule monadic_rewrite_alternative_l)
                apply (rule monadic_rewrite_symb_exec_r[OF curDomain_inv],
                        simp only: curDomain_def, rule non_fail_gets)
                 apply (rename_tac "curDom")
                 apply (rule monadic_rewrite_symb_exec_r[OF threadGet_inv no_fail_threadGet])
                  apply (rename_tac "destDom")
                  apply (rule monadic_rewrite_if_rhs[rotated])
                   apply (rule monadic_rewrite_alternative_l)
                  apply (rule monadic_rewrite_trans,
                         rule monadic_rewrite_pick_alternative_1)
                  apply (rule monadic_rewrite_symb_exec_l[OF get_mrs_inv' empty_fail_getMRs])
                   apply (rule monadic_rewrite_trans)
                    apply (rule_tac F=True and E=True in monadic_rewrite_weaken)
                    apply simp
                    apply (rule monadic_rewrite_bind_tail)
                     apply (rule_tac x=thread in monadic_rewrite_symb_exec,
                            wp empty_fail_getCurThread)
                     apply (simp add: sendIPC_def bind_assoc)
                     apply (rule_tac x=send_ep in monadic_rewrite_symb_exec,
                            wp empty_fail_getEndpoint getEndpoint_obj_at')
                     apply (rule_tac P="epQueue send_ep \<noteq> []" in monadic_rewrite_gen_asm)
                     apply (simp add: isRecvEP_endpoint_case list_case_helper bind_assoc)
                     apply (rule monadic_rewrite_bind_tail)
                      apply (rule_tac x=destState in monadic_rewrite_symb_exec,
                             wp empty_fail_getThreadState)
                     apply (rule monadic_rewrite_symb_exec2, (wp | simp)+)
                      apply (rule monadic_rewrite_bind)
                        apply (rule_tac msgInfo=msgInfo in doIPCTransfer_simple_rewrite)
                       apply (rule monadic_rewrite_bind_tail)
                        apply (rule monadic_rewrite_bind)
                          apply (rule_tac curPrio=curPrio and destPrio=destPrio
                                      and curDom=curDom and destDom=destDom and thread=thread
                                      in attemptSwitchTo_rewrite)
                         apply (rule monadic_rewrite_symb_exec2, wp empty_fail_threadGet)
                         apply (rule monadic_rewrite_bind)
                           apply (rule monadic_rewrite_trans)
                            apply (rule setupCallerCap_rewrite)
                           apply (rule monadic_rewrite_bind_head)
                           apply (rule setThreadState_blocked_rewrite, simp)
                          apply (rule monadic_rewrite_trans)
                           apply (rule_tac x=BlockedOnReply in monadic_rewrite_symb_exec,
                                  wp empty_fail_getThreadState)
                           apply simp
                           apply (rule monadic_rewrite_refl)
                          apply (rule monadic_rewrite_trans)
                           apply (rule monadic_rewrite_bind_head)
                           apply (rule_tac t="hd (epQueue send_ep)" in schedule_rewrite_ct_not_runnable')
                          apply (simp add: bind_assoc)
                          apply (rule monadic_rewrite_bind_tail)
                           apply (rule monadic_rewrite_bind)
                             apply (rule switchToThread_rewrite)
                            apply (rule activateThread_simple_rewrite)
                           apply ((wp setCurThread_ct_in_state Arch_switchToThread_st_tcb'
                                     | simp only: st_tcb_at'_def[symmetric])+)[1]
                          apply (wp, clarsimp simp: cur_tcb'_def ct_in_state'_def)
                         apply (simp add: getThreadCallerSlot_def getThreadReplySlot_def
                                          locateSlot_conv ct_in_state'_def cur_tcb'_def)
                         apply ((wp assert_inv threadSet_st_tcb_at_state cteInsert_obj_at'_not_queued | wps)+)[1]
                        apply (simp add: setSchedulerAction_def)
                        apply wp[1]
                       apply (simp cong: if_cong conj_cong add: if_bool_simps)
                       apply (simp_all only:)[4]
                       apply ((wp setThreadState_oa_queued[of _ "\<lambda>a _ _. \<not> a"]
                                 setThreadState_obj_at_unchanged
                                 asUser_obj_at_unchanged mapM_x_wp'
                                 sts_st_tcb_at'_cases
                                 setThreadState_no_sch_change
                                 setEndpoint_obj_at_tcb'
                                    | simp add: setMessageInfo_def)+)
                   apply (simp add: setThreadState_runnable_simp
                                    getThreadCallerSlot_def getThreadReplySlot_def
                                    locateSlot_conv bind_assoc)
                   apply (rule_tac P="inj (case_bool thread (hd (epQueue send_ep)))"
                                in monadic_rewrite_gen_asm)
                   apply (rule monadic_rewrite_trans[OF _ monadic_rewrite_transverse])
                     apply (rule monadic_rewrite_weaken[where F=False and E=True], simp)
                     apply (rule isolate_thread_actions_rewrite_bind
                                 fastpath_isolate_rewrites fastpath_isolatables
                                 bool.simps setRegister_simple
                                 zipWithM_setRegister_simple
                                 thread_actions_isolatable_bind
                             | assumption
                             | wp assert_inv)+
                   apply (rule_tac P="\<lambda>s. ksSchedulerAction s = ResumeCurrentThread
                                      \<and> tcb_at' thread s"
                             and F=True and E=False in monadic_rewrite_weaken)
                 apply (rule monadic_rewrite_isolate_final)
                   apply (simp add: isRight_case_sum cong: list.case_cong)
                  apply (clarsimp simp: fun_eq_iff if_flip
                                  cong: if_cong)
                  apply (drule obj_at_ko_at', clarsimp)
                  apply (frule get_tcb_state_regs_ko_at')
                  apply (clarsimp simp: zip_map2 zip_same foldl_map
                                        foldl_fun_upd
                                        foldr_copy_register_tsrs
                                        isRight_case_sum
                                  cong: if_cong)
                  apply (simp add: upto_enum_def fromEnum_def
                                   enum_register  toEnum_def
                                   msgRegisters_unfold
                             cong: if_cong)
                  apply (clarsimp split: split_if)
                  apply (rule ext)
                  apply (simp add: badgeRegister_def msgInfoRegister_def
                                   ARMMachineTypes.badgeRegister_def
                                   ARMMachineTypes.msgInfoRegister_def
                            split: split_if)
                 apply simp
                apply (wp | simp cong: if_cong bool.case_cong
                          | rule getCTE_wp' gts_wp' threadGet_wp
                                 getEndpoint_wp)+
        apply (rule validE_cases_valid)
        apply (simp add: isRight_def getSlotCap_def)
        apply (wp getCTE_wp')
        apply (rule resolveAddressBits_points_somewhere)
       apply (simp cong: if_cong bool.case_cong)
       apply wp[1]
      apply simp
      apply (wp user_getreg_wp user_getregs_wp
                threadGet_wp)
  apply (clarsimp simp: ct_in_state'_def st_tcb_at_tcb_at')
  apply (frule cte_wp_at_valid_objs_valid_cap', clarsimp+)
  apply (clarsimp simp: isCap_simps valid_cap'_def maskCapRights_def)
  apply (frule ko_at_valid_ep', clarsimp)
  apply (frule sym_refs_ko_atD'[where 'a=endpoint], clarsimp)
  apply (clarsimp simp: valid_ep'_def isRecvEP_endpoint_case neq_Nil_conv
                        tcbVTableSlot_def cte_level_bits_def
                        cte_at_tcb_at_16' length_msgRegisters
                        n_msgRegisters_def order_less_imp_le
                        ep_q_refs_of'_def st_tcb_at_refs_of_rev'
                  cong: if_cong)
  apply (rename_tac blockedThread ys tcba tcbb st v tcbc)
  apply (frule invs_mdb')
  apply (thin_tac "Ball S P" for S P)+
  apply (clarsimp simp: invs'_def valid_state'_def)
  apply (frule_tac t="blockedThread" in valid_queues_not_runnable_not_queued)
    apply (simp)
   apply (clarsimp simp: st_tcb_at'_def obj_at'_def objBits_simps projectKOs
                        valid_mdb'_def valid_mdb_ctes_def inj_case_bool
                 split: bool.split)+
  apply (simp(no_asm) add: eq_commute)
  apply (clarsimp simp: sch_act_simple_def)
  done

lemmas fastpath_call_ccorres_callKernel
    = monadic_rewrite_ccorres_assemble[OF fastpath_call_ccorres fastpath_callKernel_SysCall_corres]

lemma capability_case_Null_ReplyCap:
  "(case cap of NullCap \<Rightarrow> f | ReplyCap t b \<Rightarrow> g t b | _ \<Rightarrow> h)
     = (if isReplyCap cap then g (capTCBPtr cap) (capReplyMaster cap)
             else if isNullCap cap then f else h)"
  by (simp add: isCap_simps split: capability.split)

end

definition
 "only_cnode_caps ctes =
    option_map ((\<lambda>x. if isCNodeCap x then CTE x nullMDBNode else makeObject) o cteCap) o ctes"

context kernel_m begin

lemma in_getCTE_slot:
  "(\<exists>s. (rv, s) \<in> fst (getCTE slot s)) = (is_aligned slot cte_level_bits)"
  apply (simp add: getCTE_assert_opt exec_gets assert_opt_member)
  apply (rule iffI)
   apply clarsimp
   apply (subgoal_tac "cte_wp_at' (op = rv) slot s")
    apply (simp add: cte_wp_at_cases')
    apply (erule disjE)
     apply simp
    apply clarsimp
    apply (drule(1) tcb_cte_cases_aligned[where cte=rv])
    apply (simp add: objBits_simps cte_level_bits_def)
   apply (simp add: cte_wp_at_ctes_of)
  apply (rule_tac x="undefined \<lparr> ksPSpace := empty (slot \<mapsto> KOCTE rv) \<rparr>" in exI)
  apply (simp add: map_to_ctes_def Let_def objBits_simps cte_level_bits_def)
  done

lemma getCTE_bind_gets_the:
  "\<lbrakk> \<And>rv. \<exists>s. (rv, s) \<in> fst (getCTE slot s)
           \<Longrightarrow> \<exists>fn. f rv = gets_the (fn o (only_cnode_caps o ctes_of));
      \<exists>v. \<forall>rv. \<not> isCNodeCap (cteCap rv) \<longrightarrow> f rv = v;
      \<exists>f'. \<forall>rv. isCNodeCap (cteCap rv) \<longrightarrow> f rv = f' (cteCap rv)
     \<rbrakk> \<Longrightarrow>
    \<exists>fn. (getCTE slot >>= f)
       = (gets_the (fn o (only_cnode_caps o ctes_of)))"
  apply (case_tac "is_aligned slot cte_level_bits")
   apply (simp add: in_getCTE_slot)
   apply (clarsimp dest!: all_rv_choice_fn_eq)
   apply (clarsimp simp: getCTE_assert_opt bind_assoc)
   apply (rule_tac x="\<lambda>ctes. case ctes slot of None \<Rightarrow> None
                          | Some cte \<Rightarrow> fn cte ctes" in exI)
   apply (clarsimp simp: exec_gets fun_eq_iff gets_the_def
                         only_cnode_caps_def assert_opt_def)
   apply (case_tac "ctes_of x slot", simp_all)
   apply (simp add: exec_gets assert_opt_def only_cnode_caps_def
                    makeObject_cte
             split: split_if)
  apply (subgoal_tac "getCTE slot = fail")
   apply (simp add: gets_the_asserts ex_const_function)
  apply (rule ext)
  apply (subgoal_tac "\<forall>rv. \<not> (\<exists>s. (rv, s) \<in> fst (getCTE slot s))")
   apply (clarsimp simp: getCTE_assert_opt fun_eq_iff exec_gets
                         assert_opt_member)
   apply (simp add: assert_opt_def split: option.split)
  apply (simp add: in_getCTE_slot)
  done

lemma getSlotCap_liftE_bindE_gets_the:
  "\<lbrakk> \<And>rv. \<exists>s. (rv, s) \<in> fst (getSlotCap slot s)
          \<Longrightarrow> \<exists>fn. f rv = gets_the (fn o (only_cnode_caps o ctes_of));
     \<exists>v. \<forall>rv. \<not> isCNodeCap rv \<longrightarrow> f rv = v
     \<rbrakk> \<Longrightarrow>
    \<exists>fn. (getSlotCap slot >>= f)
       = (gets_the (fn o (only_cnode_caps o ctes_of)))"
  apply (simp add: getSlotCap_def in_monad)
  apply (rule getCTE_bind_gets_the)
    apply fastforce
   apply clarsimp
  apply fastforce
  done

lemma resolveAddressBits_ctes_of_equality:
  "\<exists>fn. (resolveAddressBits cap cptr bits)
         = gets_the (fn o (only_cnode_caps o ctes_of))"
proof (induct cap cptr bits rule: resolveAddressBits.induct)
  case (1 acap acptr abits)
  show ?case
    apply (subst resolveAddressBits.simps)
    apply (clarsimp simp: gets_the_returns
                          ex_const_function
                          assertE_def whenE_def unlessE_def
                          gets_the_asserts locateSlot_conv
                          liftE_bindE
                   split: split_if simp del: imp_disjL)
    apply (rule getSlotCap_liftE_bindE_gets_the)
     apply (clarsimp simp: gets_the_returns
                           ex_const_function unlessE_def
                    split: capability.split split_if)
     apply (rule "1.hyps", (rule conjI refl | assumption
                                 | simp add: in_monad locateSlot_conv)+)
    apply (simp add: cnode_cap_case_if)
    done
qed

definition
  "resolveAddressBits_functional
      = (\<lambda>cap cptr bits. SOME fn. resolveAddressBits cap cptr bits
                      = gets_the (fn o (only_cnode_caps o ctes_of)))"

lemma resolveAddressBits_def_functional:
  "resolveAddressBits cap cptr bits
       = gets_the (resolveAddressBits_functional cap cptr bits o (only_cnode_caps o ctes_of))"
  unfolding resolveAddressBits_functional_def
  using resolveAddressBits_ctes_of_equality[of cap cptr bits]
  apply (elim exE)
  apply (erule_tac P="\<lambda>fn. ra = gets_the (fn o (only_cnode_caps o ctes_of))" for ra in someI)
  done

lemma injection_handler_catch:
  "catch (injection_handler f x) y
      = catch x (y o f)"
  apply (simp add: injection_handler_def catch_def handleE'_def
                   bind_assoc)
  apply (rule bind_cong[OF refl])
  apply (simp add: throwError_bind split: sum.split)
  done

lemma doReplyTransfer_simple:
  "monadic_rewrite True False
     (obj_at' (\<lambda>tcb. tcbFault tcb = None) receiver)
     (doReplyTransfer sender receiver slot)
     (do state \<leftarrow> getThreadState receiver;
         assert (isReply state);
         cte \<leftarrow> getCTE slot;
         mdbnode \<leftarrow> return $ cteMDBNode cte;
         assert (mdbPrev mdbnode \<noteq> 0 \<and> mdbNext mdbnode = 0);
         parentCTE \<leftarrow> getCTE (mdbPrev mdbnode);
         assert (isReplyCap (cteCap parentCTE) \<and> capReplyMaster (cteCap parentCTE));
         doIPCTransfer sender Nothing 0 True receiver False;
         cteDeleteOne slot;
         setThreadState Running receiver;
         attemptSwitchTo receiver
         od )"
  apply (simp add: doReplyTransfer_def liftM_def nullPointer_def
                   getSlotCap_def)
  apply (rule monadic_rewrite_bind_tail)+
        apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_threadGet)
         apply (rule_tac P="rv = None" in monadic_rewrite_gen_asm, simp)
         apply (rule monadic_rewrite_refl)
        apply (wp threadGet_const gts_wp' getCTE_wp')
  apply (simp add: o_def)
  done

lemma receiveIPC_simple_rewrite:
  "monadic_rewrite True False
     ((\<lambda>_. isEndpointCap ep_cap \<and> \<not> isSendEP ep) and ko_at' ep (capEPPtr ep_cap))
     (receiveIPC thread ep_cap)
     (do
       setThreadState (BlockedOnReceive (capEPPtr ep_cap) (\<not> capEPCanSend ep_cap)) thread;
       setEndpoint (capEPPtr ep_cap) (RecvEP (case ep of RecvEP q \<Rightarrow> (q @ [thread]) | _ \<Rightarrow> [thread]))
      od)"
  apply (rule monadic_rewrite_gen_asm)
  apply (simp add: receiveIPC_def)
  apply (cases ep, simp_all add: isSendEP_def)
   apply (rule monadic_rewrite_imp)
    apply (rule_tac rv=ep in monadic_rewrite_symb_exec_l_known,
           wp empty_fail_getEndpoint)
     apply simp
     apply (rule monadic_rewrite_refl)
    apply (wp getEndpoint_obj_at')
   apply simp
  apply (rule monadic_rewrite_imp)
   apply (rule_tac rv=ep in monadic_rewrite_symb_exec_l_known,
          wp empty_fail_getEndpoint)
    apply simp
    apply (rule monadic_rewrite_refl)
   apply (wp getEndpoint_obj_at')
  apply simp
  done

lemma empty_fail_isFinalCapability:
  "empty_fail (isFinalCapability cte)"
  by (simp add: isFinalCapability_def Let_def split: split_if)

lemma cteDeleteOne_replycap_rewrite:
  "monadic_rewrite True False
     (cte_wp_at' (\<lambda>cte. isReplyCap (cteCap cte)) slot)
     (cteDeleteOne slot)
     (emptySlot slot None)"
  apply (simp add: cteDeleteOne_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_getCTE)
    apply (rule_tac P="cteCap rv \<noteq> NullCap \<and> isReplyCap (cteCap rv)
                          \<and> \<not> isEndpointCap (cteCap rv)
                          \<and> \<not> isAsyncEndpointCap (cteCap rv)"
             in monadic_rewrite_gen_asm)
    apply (simp add: finaliseCapTrue_standin_def
                     capRemovable_def)
    apply (rule monadic_rewrite_symb_exec_l,
           wp isFinalCapability_inv empty_fail_isFinalCapability)
     apply (rule monadic_rewrite_refl)
    apply (wp getCTE_wp')
  apply (clarsimp simp: cte_wp_at_ctes_of isCap_simps)
  done

lemma cteDeleteOne_nullcap_rewrite:
  "monadic_rewrite True False
     (cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) slot)
     (cteDeleteOne slot)
     (return ())"
  apply (simp add: cteDeleteOne_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_getCTE)
    apply (rule_tac P="cteCap rv = NullCap" in monadic_rewrite_gen_asm)
    apply simp
    apply (rule monadic_rewrite_refl)
   apply (wp getCTE_wp')
  apply (clarsimp simp: cte_wp_at_ctes_of)
  done

end

lemma emptySlot_cnode_caps:
  "\<lbrace>\<lambda>s. P (only_cnode_caps (ctes_of s)) \<and> cte_wp_at' (\<lambda>cte. \<not> isCNodeCap (cteCap cte)) slot s\<rbrace>
     emptySlot slot None
   \<lbrace>\<lambda>rv s. P (only_cnode_caps (ctes_of s))\<rbrace>"
  apply (simp add: only_cnode_caps_def option_map_comp2
                   o_assoc[symmetric] cteCaps_of_def[symmetric])
  apply (wp emptySlot_cteCaps_of)
  apply (clarsimp simp: cteCaps_of_def cte_wp_at_ctes_of
                 elim!: rsubst[where P=P] intro!: ext
                 split: split_if)
  done

lemma cteDeleteOne_cnode_caps:
  "\<lbrace>\<lambda>s. P (only_cnode_caps (ctes_of s))\<rbrace>
     cteDeleteOne slot
   \<lbrace>\<lambda>rv s. P (only_cnode_caps (ctes_of s))\<rbrace>"
  apply (simp add: only_cnode_caps_def option_map_comp2
                   o_assoc[symmetric] cteCaps_of_def[symmetric])
  apply (wp cteDeleteOne_cteCaps_of)
  apply clarsimp
  apply (erule rsubst[where P=P], rule ext)
  apply (clarsimp simp: cteCaps_of_def cte_wp_at_ctes_of isCap_simps)
  apply (rule_tac x="cteCap cte" in exI)
  apply (clarsimp simp: finaliseCap_def finaliseCapTrue_standin_def isCap_simps)
  done

lemma asUser_obj_at_ep[wp]:
  "\<lbrace>obj_at' P p\<rbrace> asUser t m \<lbrace>\<lambda>rv. obj_at' (P :: endpoint \<Rightarrow> bool) p\<rbrace>"
  apply (simp add: asUser_def split_def)
  apply (wp hoare_drop_imps | simp)+
  done

lemma setCTE_obj_at_ep[wp]:
  "\<lbrace>obj_at' (P :: endpoint \<Rightarrow> bool) p\<rbrace> setCTE ptr cte \<lbrace>\<lambda>rv. obj_at' P p\<rbrace>"
  unfolding setCTE_def
  apply (rule obj_at_setObject2)
  apply (clarsimp simp: updateObject_cte typeError_def in_monad
                 split: Structures_H.kernel_object.split_asm
                        split_if_asm)
  done

crunch obj_at_ep[wp]: emptySlot "obj_at' (P :: endpoint \<Rightarrow> bool) p"

crunch nosch[wp]: emptySlot "\<lambda>s. P (ksSchedulerAction s)"

crunch ctes_of[wp]: attemptSwitchTo "\<lambda>s. P (ctes_of s)"
  (wp: crunch_wps)

crunch cte_wp_at'[wp]: attemptSwitchTo "cte_wp_at' P p"

crunch tcbContext[wp]: attemptSwitchTo "obj_at' (\<lambda>tcb. P (tcbContext tcb)) t"
  (wp: crunch_wps)

crunch only_cnode_caps[wp]: doFaultTransfer "\<lambda>s. P (only_cnode_caps (ctes_of s))"
  (wp: crunch_wps simp: crunch_simps)

context kernel_m begin

lemma tcbSchedDequeue_rewrite_not_queued: "monadic_rewrite True False (tcb_at' t and obj_at' (Not \<circ> tcbQueued) t) (tcbSchedDequeue t) (return ())"
  apply (simp add: tcbSchedDequeue_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule_tac P="\<not> queued" in monadic_rewrite_gen_asm)
     apply (simp add: when_def)
     apply (rule monadic_rewrite_refl)
    apply (wp threadGet_const)

   apply (rule monadic_rewrite_symb_exec_l)
      apply wp
    apply (rule monadic_rewrite_refl)
   apply (wp)
  apply (clarsimp simp: o_def obj_at'_def)
done

lemma schedule_known_rewrite:
  "monadic_rewrite True False
      (\<lambda>s. ksSchedulerAction s = SwitchToThread t
               \<and> tcb_at' t s
               \<and> obj_at' (Not \<circ> tcbQueued) t s
               \<and> ksCurThread s = t'
               \<and> st_tcb_at' (Not \<circ> runnable') t' s)
      (schedule)
      (do ArchThreadDecls_H.switchToThread t;
          setCurThread t;
          setSchedulerAction ResumeCurrentThread od)"
  apply (simp add: schedule_def)
  apply (simp only: switchToThread_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_bind_tail)
      apply (rule_tac P="action = SwitchToThread t" in monadic_rewrite_gen_asm,simp)
      apply (rule monadic_rewrite_bind_tail)
       apply (rule_tac P="\<not> curRunnable \<and> action = SwitchToThread t" in monadic_rewrite_gen_asm, simp)
       apply (simp add: bind_assoc)
       apply (rule monadic_rewrite_bind_tail)
        apply (rule monadic_rewrite_bind)
          apply (rule monadic_rewrite_trans)
           apply (rule tcbSchedDequeue_rewrite_not_queued)
          apply (rule monadic_rewrite_refl)
         apply (rule monadic_rewrite_bind_tail)
          apply (rule monadic_rewrite_refl)
         apply (wp Arch_switchToThread_obj_at_pre, simp, wp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_rewrite_symb_exec_l)
       apply (wp)
      apply simp
     apply (rule monadic_rewrite_symb_exec_l)
        apply wp
       apply (simp add: getSchedulerAction_def)
      apply (rule monadic_rewrite_symb_exec_l)
         apply (wp)
        apply (simp add: isRunnable_def)
       apply (rule monadic_rewrite_bind_tail)
        apply (rule monadic_rewrite_symb_exec_l)
           apply (wp, simp)
         apply (rule monadic_rewrite_bind_tail)
          apply (rule monadic_rewrite_refl)
         apply (wp)
   apply (rule monadic_rewrite_refl)
   apply (clarsimp simp: st_tcb_at'_def o_def obj_at'_def)
done

lemma setThreadState_schact_set:
  "monadic_rewrite True False
     (\<lambda>s. ksSchedulerAction s \<noteq> ResumeCurrentThread)
     (setThreadState st t)
     (threadSet (tcbState_update (\<lambda>_. st)) t)"
  apply (simp add: setThreadState_def)
  apply (rule monadic_rewrite_imp)
   apply (subst bind_return[symmetric], rule monadic_rewrite_bind_tail)
    apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_isRunnable)
     apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_getCurThread)
      apply (rule monadic_rewrite_symb_exec_l, wp)
        apply (simp add: getSchedulerAction_def)
       apply (rename_tac sa)
       apply (rule_tac P="sa \<noteq> ResumeCurrentThread" in monadic_rewrite_gen_asm)
       apply (simp add: when_def)
       apply (rule monadic_rewrite_refl)
      apply (wp | simp)+
  done

lemma tcb_at_cte_at_offset:
  "\<lbrakk> tcb_at' t s; 2 ^ cte_level_bits * off \<in> dom tcb_cte_cases \<rbrakk>
    \<Longrightarrow> cte_at' (t + 2 ^ cte_level_bits * off) s"
  apply (clarsimp simp: obj_at'_def projectKOs objBits_simps)
  apply (erule(2) cte_wp_at_tcbI')
   apply fastforce
  apply simp
  done

end

lemma no_fail_getSlotCap_fun:
  "\<lbrakk> \<And>rv s. (rv, s) \<in> fst (getSlotCap p s) \<Longrightarrow> no_fail (P rv) (f rv) \<rbrakk>
      \<Longrightarrow> no_fail (\<lambda>s. \<exists>rv. ctes_of s p = Some rv \<and> P (cteCap rv) s)
             (getSlotCap p >>= f)"
  apply (simp add: getSlotCap_def in_monad)
  apply (clarsimp simp: no_fail_def snd_bind in_getCTE2 Ball_def
                        no_failD[OF no_fail_getCTE] cte_wp_at_ctes_of)
  apply fastforce
  done

lemma resolveAddressBits_no_fail:
  "no_fail (valid_objs' and valid_cap' c)
       (resolveAddressBits c cptr bits)"
proof (induct c cptr bits
           rule: resolveAddressBits.induct)
  case (1 cap ptr n)
  show ?case
    apply (subst resolveAddressBits.simps)
    apply (simp add: Let_def locateSlot_conv split_def unlessE_def
                     whenE_def assertE_def if_to_top_of_bindE
                     liftE_bindE
                del: resolveAddressBits.simps split del: split_if
               cong: if_cong capability.case_cong)
    apply (rule no_fail_pre)
     apply (wp no_fail_getSlotCap_fun
                  | simp del: resolveAddressBits.simps | wpc)+
          apply (rule "1.hyps",
                 (rule refl conjI
                   | simp add: in_monad locateSlot_conv)+)
         apply wp
    apply (clarsimp simp: if_apply_def2 isCap_simps valid_cap_simps'
                simp del: imp_disjL)
    apply (drule spec, drule real_cte_at')
    apply (clarsimp simp: cte_wp_at_ctes_of cte_level_bits_def)
    apply (frule(1) ctes_of_valid')
    apply (fastforce simp: valid_cap_simps')
    done
qed

context kernel_m begin

lemma resolveAddressBits_functional_Some:
  "valid_objs' s \<and> s \<turnstile>' c
      \<longrightarrow> resolveAddressBits_functional c cptr bits (only_cnode_caps (ctes_of s)) \<noteq> None"
  using resolveAddressBits_no_fail[where c=c and cptr=cptr and bits=bits]
  apply (clarsimp simp: resolveAddressBits_def_functional gets_the_def
                        no_fail_def exec_gets assert_opt_def fail_def
                 split: option.split_asm)
  apply fastforce
  done

lemma attemptSwitchTo_rewrite2:
  "monadic_rewrite True True
      (\<lambda>s. obj_at' (\<lambda>tcb. tcbPriority tcb = curPrio) ct s
             \<and> obj_at' (\<lambda>tcb. tcbPriority tcb = destPrio \<and> tcbDomain tcb = destDom) t s
             \<and> curPrio \<le> destPrio \<and> ct = ksCurThread s
             \<and> ksSchedulerAction s = ResumeCurrentThread
             \<and> curDom = ksCurDomain s \<and> destDom = curDom)
      (attemptSwitchTo t) (setSchedulerAction (SwitchToThread t))"
  apply (rule monadic_rewrite_imp,
        rule attemptSwitchTo_rewrite[where thread=ct and curPrio=curPrio and destPrio=destPrio
                                              and curDom=curDom and destDom=destDom])
  apply clarsimp
  done

lemma emptySlot_cte_wp_at_cteCap:
  "\<lbrace>\<lambda>s. (p = p' \<longrightarrow> P NullCap) \<and> (p \<noteq> p' \<longrightarrow> cte_wp_at' (\<lambda>cte. P (cteCap cte)) p s)\<rbrace>
     emptySlot p' irqopt
   \<lbrace>\<lambda>rv s. cte_wp_at' (\<lambda>cte. P (cteCap cte)) p s\<rbrace>"
  apply (simp add: tree_cte_cteCap_eq[unfolded o_def])
  apply (wp emptySlot_cteCaps_of)
  apply (clarsimp split: split_if)
  done

lemma resolveAddressBits_functional_real_cte_at':
  "[| resolveAddressBits_functional c ptr bits (only_cnode_caps (ctes_of s)) = Some val;
      isRight val; valid_objs' s; valid_cap' c s |]
     ==> real_cte_at' (fst (theRight val)) s"
  using resolveAddressBits_real_cte_at'[where cap=c and addr=ptr and depth=bits]
  apply (clarsimp simp: resolveAddressBits_def_functional isRight_def)
  apply (drule use_validE_R[rotated])
    apply fastforce
   apply (fastforce simp add: gets_the_member)
  apply simp
  done

lemma real_cte_at_tcbs_of_neq:
  "[| real_cte_at' p s; tcbs_of s t = Some tcb;
         2 ^ cte_level_bits * offs : dom tcb_cte_cases |]
       ==> p ~= t + 2 ^ cte_level_bits * offs"
  apply (clarsimp simp: tcbs_of_def obj_at'_def projectKOs objBits_simps
                 split: split_if_asm)
  apply (erule notE[rotated], erule(2) tcb_ctes_clear[rotated])
  apply fastforce
  done

lemma setEndpoint_getCTE_pivot[unfolded K_bind_def]:
  "do setEndpoint p val; v <- getCTE slot; f v od
     = do v <- getCTE slot; setEndpoint p val; f v od"
  apply (simp add: getCTE_assert_opt setEndpoint_def
                   setObject_modify_assert
                   fun_eq_iff bind_assoc)
  apply (simp add: exec_gets assert_def assert_opt_def
                   exec_modify update_ep_map_tos
            split: split_if option.split)
  done

lemma setEndpoint_setCTE_pivot[unfolded K_bind_def]:
  "do setEndpoint p val; setCTE slot cte; f od =
     do setCTE slot cte; setEndpoint p val; f od"
  apply (rule monadic_rewrite_to_eq)
  apply simp
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans,
          rule_tac f="ep_at' p" in monadic_rewrite_add_gets)
   apply (rule monadic_rewrite_transverse, rule monadic_rewrite_add_gets,
          rule monadic_rewrite_bind_tail)
    apply (rename_tac epat)
    apply (rule monadic_rewrite_transverse)
     apply (rule monadic_rewrite_bind_tail)
      apply (simp add: setEndpoint_def setObject_modify_assert bind_assoc)
      apply (rule_tac rv=epat in monadic_rewrite_gets_known)
     apply (wp setCTE_typ_at'[where T="koType TYPE(endpoint)", unfolded typ_at_to_obj_at']
                  | simp)+
    apply (simp add: setCTE_assert_modify bind_assoc)
    apply (rule monadic_rewrite_trans, rule monadic_rewrite_add_gets,
           rule monadic_rewrite_bind_tail)+
      apply (rename_tac cteat tcbat)
      apply (rule monadic_rewrite_trans, rule monadic_rewrite_bind_tail)
        apply (rule monadic_rewrite_trans)
         apply (rule_tac rv=cteat in monadic_rewrite_gets_known)
        apply (rule_tac rv=tcbat in monadic_rewrite_gets_known)
       apply (wp setEndpoint_typ_at'[where T="koType TYPE(tcb)", unfolded typ_at_to_obj_at']
                 setEndpoint_typ_at'[where T="koType TYPE(cte)", unfolded typ_at_to_obj_at']
                     | simp)+
      apply (rule_tac P="\<lambda>s. epat = ep_at' p s \<and> cteat = real_cte_at' slot s
                           \<and> tcbat = (tcb_at' (slot && ~~ mask 9) and (%y. slot && mask 9 : dom tcb_cte_cases)) s"
                   in monadic_rewrite_refl3)
      apply (simp add: setEndpoint_def setObject_modify_assert bind_assoc
                       exec_gets assert_def exec_modify
                split: split_if)
      apply (auto split: split_if simp: obj_at'_def projectKOs
                 intro!: arg_cong[where f=f] ext kernel_state.fold_congs)[1]
     apply wp
  apply simp
  done

lemma setEndpoint_updateMDB_pivot[unfolded K_bind_def]:
  "do setEndpoint p val; updateMDB slot mf; f od =
     do updateMDB slot mf; setEndpoint p val; f od"
  by (clarsimp simp: updateMDB_def bind_assoc
                     setEndpoint_getCTE_pivot
                     setEndpoint_setCTE_pivot
              split: split_if)

lemma setEndpoint_updateCap_pivot[unfolded K_bind_def]:
  "do setEndpoint p val; updateCap slot mf; f od =
     do updateCap slot mf; setEndpoint p val; f od"
  by (clarsimp simp: updateCap_def bind_assoc
                     setEndpoint_getCTE_pivot
                     setEndpoint_setCTE_pivot)

lemma emptySlot_setEndpoint_pivot[unfolded K_bind_def]:
  "(do emptySlot slot None; setEndpoint p val; f od) =
      (do setEndpoint p val; emptySlot slot None; f od)"
  apply (rule ext)
  apply (simp add: emptySlot_def bind_assoc
                   setEndpoint_getCTE_pivot
                   setEndpoint_updateCap_pivot
                   setEndpoint_updateMDB_pivot
            split: split_if
              | rule bind_apply_cong[OF refl])+
  done

lemma set_getCTE[unfolded K_bind_def]:
  "do setCTE p cte; v <- getCTE p; f v od
      = do setCTE p cte; f cte od"
  apply simp
  apply (rule monadic_rewrite_to_eq)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_bind_tail)
    apply (simp add: getCTE_assert_opt bind_assoc)
    apply (rule monadic_rewrite_trans,
           rule_tac rv="Some cte" in monadic_rewrite_gets_known)
    apply (simp add: assert_opt_def)
    apply (rule monadic_rewrite_refl)
   apply wp
  apply simp
  done

lemma set_setCTE[unfolded K_bind_def]:
  "do setCTE p val; setCTE p val' od = setCTE p val'"
  apply simp
  apply (rule monadic_rewrite_to_eq)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans,
          rule_tac f="real_cte_at' p" in monadic_rewrite_add_gets)
   apply (rule monadic_rewrite_transverse, rule monadic_rewrite_add_gets,
          rule monadic_rewrite_bind_tail)
    apply (rule monadic_rewrite_trans,
           rule_tac f="tcb_at' (p && ~~ mask 9) and K (p && mask 9 \<in> dom tcb_cte_cases)"
                  in monadic_rewrite_add_gets)
    apply (rule monadic_rewrite_transverse, rule monadic_rewrite_add_gets,
           rule monadic_rewrite_bind_tail)
     apply (rename_tac cteat tcbat)
     apply (rule monadic_rewrite_trans)
      apply (rule monadic_rewrite_bind_tail)
       apply (simp add: setCTE_assert_modify)
       apply (rule monadic_rewrite_trans, rule_tac rv=cteat in monadic_rewrite_gets_known)
       apply (rule_tac rv=tcbat in monadic_rewrite_gets_known)
      apply (wp setCTE_typ_at'[where T="koType TYPE(tcb)", unfolded typ_at_to_obj_at']
                setCTE_typ_at'[where T="koType TYPE(cte)", unfolded typ_at_to_obj_at']
                  | simp)+
     apply (simp add: setCTE_assert_modify bind_assoc)
     apply (rule monadic_rewrite_bind_tail)+
       apply (rule_tac P="c = cteat \<and> t = tcbat
                           \<and> (tcbat \<longrightarrow>
                                 (\<exists> getF setF. tcb_cte_cases (p && mask 9) = Some (getF, setF)
                                        \<and> (\<forall> f g tcb. setF f (setF g tcb) = setF (f o g) tcb)))"
                   in monadic_rewrite_gen_asm)
       apply (rule monadic_rewrite_refl2)
       apply (simp add: exec_modify split: split_if)
       apply (auto simp: simpler_modify_def projectKO_opt_tcb
                 intro!: kernel_state.fold_congs ext
                  split: split_if)[1]
      apply wp
  apply (clarsimp intro!: all_tcbI)
  apply (auto simp: tcb_cte_cases_def split: split_if_asm)
  done

lemma setCTE_updateCapMDB:
  "p \<noteq> 0 \<Longrightarrow>
   setCTE p cte = do updateCap p (cteCap cte); updateMDB p (const (cteMDBNode cte)) od"
  apply (simp add: updateCap_def updateMDB_def bind_assoc set_getCTE
                   cte_overwrite set_setCTE)
  apply (simp add: getCTE_assert_opt setCTE_assert_modify bind_assoc)
  apply (rule ext, simp add: exec_gets assert_opt_def exec_modify
                      split: split_if option.split)
  apply (cut_tac P=\<top> and p=p and s=x in cte_wp_at_ctes_of)
  apply (cases cte)
  apply (simp add: cte_wp_at_obj_cases')
  apply (auto simp: mask_out_sub_mask)
  done

lemma emptySlot_replymaster_rewrite[OF refl]:
  "mdbn = cteMDBNode cte \<Longrightarrow>
   monadic_rewrite True False
     ((\<lambda>_. mdbNext mdbn = 0 \<and> mdbPrev mdbn \<noteq> 0)
           and ((\<lambda>_. cteCap cte \<noteq> NullCap)
           and (cte_wp_at' (op = cte) slot
           and cte_wp_at' (\<lambda>cte. isReplyCap (cteCap cte) \<and> capReplyMaster (cteCap cte))
                    (mdbPrev mdbn)
           and (\<lambda>s. reply_masters_rvk_fb (ctes_of s))
           and (\<lambda>s. no_0 (ctes_of s)))))
     (emptySlot slot None)
     (do updateMDB (mdbPrev mdbn) (mdbNext_update (K 0) o mdbFirstBadged_update (K True)
                                              o mdbRevocable_update (K True));
         setCTE slot makeObject
      od)"
  apply (rule monadic_rewrite_gen_asm)+
  apply (rule monadic_rewrite_imp)
   apply (rule_tac P="slot \<noteq> 0" in monadic_rewrite_gen_asm)
   apply (clarsimp simp: emptySlot_def setCTE_updateCapMDB)
   apply (rule_tac rv=cte in monadic_rewrite_symb_exec_l_known, wp empty_fail_getCTE)
    apply (simp add: updateMDB_def Let_def bind_assoc makeObject_cte)
    apply (rule monadic_rewrite_bind_tail)
     apply (rule monadic_rewrite_bind)
       apply (rule_tac P="mdbFirstBadged (cteMDBNode ctea) \<and> mdbRevocable (cteMDBNode ctea)"
                   in monadic_rewrite_gen_asm)
       apply (rule monadic_rewrite_refl2)
       apply (case_tac ctea, rename_tac mdbnode, case_tac mdbnode)
       apply simp
      apply (rule monadic_rewrite_refl)
     apply (wp getCTE_wp')
  apply (clarsimp simp: cte_wp_at_ctes_of reply_masters_rvk_fb_def)
  apply fastforce
  done

(* FIXME: Move *)
lemma asUser_obj_at_not_queued[wp]:
  "\<lbrace>obj_at' (\<lambda>tcb. \<not> tcbQueued tcb) p\<rbrace> asUser t m \<lbrace>\<lambda>rv. obj_at' (\<lambda>tcb. \<not> tcbQueued tcb) p\<rbrace>"
  apply (simp add: asUser_def split_def)
  apply (wp hoare_drop_imps | simp)+
  done

lemma all_prio_not_inQ_not_tcbQueued: "\<lbrakk> obj_at' (\<lambda>a. (\<forall>d p. \<not> inQ d p a)) t s \<rbrakk> \<Longrightarrow> obj_at' (\<lambda>a. \<not> tcbQueued a) t s"
  apply (clarsimp simp: obj_at'_def inQ_def)
done

lemma st_tcb_at_is_Reply_imp_not_tcbQueued: "\<And>s t.\<lbrakk> invs' s; st_tcb_at' isReply t s\<rbrakk> \<Longrightarrow> obj_at' (\<lambda>a. \<not> tcbQueued a) t s"
  apply (clarsimp simp: invs'_def valid_state'_def valid_queues_def st_tcb_at'_def)
  apply (rule all_prio_not_inQ_not_tcbQueued)
  apply (clarsimp simp: obj_at'_def)
  apply (erule_tac x="d" in allE)
  apply (erule_tac x="p" in allE)
  apply (erule conjE)
  apply (erule_tac x="t" in ballE)
   apply (clarsimp simp: obj_at'_def runnable'_def isReply_def)
   apply (case_tac "tcbState obj")
          apply ((clarsimp simp: inQ_def)+)[8]
  apply (clarsimp simp: valid_queues'_def obj_at'_def)
done

lemma fastpath_callKernel_SysReplyWait_corres:
  "monadic_rewrite True False
     (invs' and ct_in_state' (op = Running) and (\<lambda>s. ksSchedulerAction s = ResumeCurrentThread))
     (callKernel (SyscallEvent SysReplyWait)) (fastpaths SysReplyWait)"
  apply (rule monadic_rewrite_introduce_alternative)
   apply (simp add: callKernel_def)
  apply (rule monadic_rewrite_imp)
   apply (simp add: handleEvent_def handleReply_def
                    handleWait_def liftE_bindE_handle liftE_handle
                    bind_assoc getMessageInfo_def liftE_bind)
   apply (simp add: catch_liftE_bindE unlessE_throw_catch_If
                    unifyFailure_catch_If catch_liftE
                    getMessageInfo_def alternative_bind
                    fastpaths_def getThreadCallerSlot_def
                    locateSlot_conv capability_case_Null_ReplyCap
                    getThreadCSpaceRoot_def
              cong: if_cong)
   apply (rule monadic_rewrite_rdonly_bind_l, wp)
   apply (rule monadic_rewrite_bind_tail)
    apply (rule monadic_rewrite_symb_exec_r, wp)
     apply (rename_tac msgInfo)
     apply (rule monadic_rewrite_symb_exec_r, wp)
      apply (rename_tac cptr)
      apply (rule monadic_rewrite_symb_exec_r
                     [OF threadGet_inv no_fail_threadGet])
       apply (rename_tac tcbFault)
       apply (rule monadic_rewrite_alternative_rhs[rotated])
        apply (rule monadic_rewrite_alternative_l)
       apply (rule monadic_rewrite_if_rhs[rotated])
        apply (rule monadic_rewrite_alternative_l)
       apply (simp add: lookupCap_def liftME_def lookupCapAndSlot_def
                        lookupSlotForThread_def bindE_assoc
                        split_def getThreadCSpaceRoot_def
                        locateSlot_conv liftE_bindE bindE_bind_linearise
                        capFaultOnFailure_def rethrowFailure_injection
                        injection_handler_catch bind_bindE_assoc
                        resolveAddressBits_def_functional
                        getThreadCallerSlot_def bind_assoc
                        getSlotCap_def deleteCallerCap_def
                        case_bool_If o_def
                        isRight_def[where x="Inr v" for v]
                        isRight_def[where x="Inl v" for v]
                  cong: if_cong)
       apply (rule monadic_rewrite_symb_exec_r, wp)
        apply (rename_tac "cTableCTE")

        apply (rule monadic_rewrite_symb_exec_r,
                 (wp | simp)+)
         apply (rename_tac "rab_ret")
         apply (rule_tac P="isRight rab_ret" in monadic_rewrite_cases[rotated])
          apply (case_tac rab_ret, simp_all add: isRight_def)[1]
           apply (rule monadic_rewrite_alternative_l)
          apply clarsimp
         apply (simp add: isRight_case_sum liftE_bind
                          isRight_def[where x="Inr v" for v])
         apply (rule monadic_rewrite_symb_exec_r, wp)
          apply (rename_tac ep_cap)
          apply (rule monadic_rewrite_if_rhs[rotated])
           apply (rule monadic_rewrite_alternative_l)
          apply (rule monadic_rewrite_symb_exec_r, wp)
           apply (rename_tac ep)
           apply (rule monadic_rewrite_if_rhs[rotated])
            apply (rule monadic_rewrite_alternative_l)
           apply (rule monadic_rewrite_rdonly_bind_l, wp)
           apply (rule monadic_rewrite_bind_tail)
            apply (rename_tac replyCTE)
            apply (rule monadic_rewrite_if_rhs[rotated])
             apply (rule monadic_rewrite_alternative_l)
            apply (simp add: bind_assoc)
            apply (rule monadic_rewrite_rdonly_bind_l, wp assert_inv)
            apply (rule monadic_rewrite_assert)
            apply (rule monadic_rewrite_symb_exec_r, wp)
             apply (rename_tac callerFault)
             apply (rule monadic_rewrite_if_rhs[rotated])
              apply (rule monadic_rewrite_alternative_l)
             apply (simp add: getThreadVSpaceRoot_def locateSlot_conv)
             apply (rule monadic_rewrite_symb_exec_r, wp)
              apply (rename_tac vTableCTE)
              apply (rule monadic_rewrite_if_rhs[rotated])
               apply (rule monadic_rewrite_alternative_l)
              apply (rule monadic_rewrite_symb_exec_r, wp)+
                apply (rename_tac curPrio callerPrio)
                apply (rule monadic_rewrite_if_rhs[rotated])
                 apply (rule monadic_rewrite_alternative_l)
                apply (rule monadic_rewrite_symb_exec_r, wp)
                 apply (rule monadic_rewrite_if_rhs[rotated])
                  apply (rule monadic_rewrite_alternative_l)
                 apply (rule monadic_rewrite_symb_exec_r[OF curDomain_inv],
                        simp only: curDomain_def, rule non_fail_gets)
                  apply (rename_tac "curDom")
                  apply (rule monadic_rewrite_symb_exec_r[OF threadGet_inv no_fail_threadGet])
                   apply (rename_tac "callerDom")
                   apply (rule monadic_rewrite_if_rhs[rotated])
                    apply (rule monadic_rewrite_alternative_l)
                   apply (rule monadic_rewrite_trans,
                          rule monadic_rewrite_pick_alternative_1)
                   apply (rule monadic_rewrite_trans)
                    apply (rule monadic_rewrite_trans)
                     apply (rule monadic_rewrite_bind_head)
                     apply (rule monadic_rewrite_trans)
                      apply (rule doReplyTransfer_simple)
                     apply simp
                     apply (((rule monadic_rewrite_weaken2,
                              (rule_tac msgInfo=msgInfo in doIPCTransfer_simple_rewrite
                                 | rule_tac curPrio=curPrio and destPrio=callerPrio
                                        and curDom=curDom and destDom=callerDom
                                        and ct=thread in attemptSwitchTo_rewrite2))
                              | rule cteDeleteOne_replycap_rewrite
                              | rule monadic_rewrite_bind monadic_rewrite_refl
                              | wp assert_inv mapM_x_wp'
                                   setThreadState_obj_at_unchanged
                                   asUser_obj_at_unchanged
                                   hoare_strengthen_post[OF _ obj_at_conj'[simplified atomize_conjL], rotated]
                              | simp add: setMessageInfo_def setThreadState_runnable_simp)+)[1]
                    apply (simp add: setMessageInfo_def)
                    apply (rule monadic_rewrite_bind_tail)
                     apply (rule_tac rv=thread in monadic_rewrite_symb_exec_l_known,
                            wp empty_fail_getCurThread)
                      apply (rule monadic_rewrite_bind)
                        apply (rule cteDeleteOne_nullcap_rewrite)
                       apply (rule_tac rv=cptr in monadic_rewrite_symb_exec_l_known,
                              wp empty_fail_asUser empty_fail_getRegister)
                        apply (rule monadic_rewrite_bind)
                          apply (rule monadic_rewrite_catch[OF _ monadic_rewrite_refl True_E_E])
                           apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_getCTE)
                            apply (rename_tac cTableCTE2,
                                   rule_tac P="cteCap cTableCTE2 = cteCap cTableCTE"
                                        in monadic_rewrite_gen_asm)
                            apply simp
                            apply (rule monadic_rewrite_trans,
                                   rule monadic_rewrite_bindE[OF _ monadic_rewrite_refl])
                              apply (rule_tac v=rab_ret
                                         in monadic_rewrite_gets_the_known_v)
                             apply wp
                            apply (simp add: return_bindE)
                            apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_getCTE)
                             apply (rename_tac ep_cap2)
                             apply (rule_tac P="cteCap ep_cap2 = cteCap ep_cap" in monadic_rewrite_gen_asm)
                             apply (simp add: cap_case_EndpointCap_AsyncEndpointCap)
                             apply (rule monadic_rewrite_liftE)
                             apply (rule monadic_rewrite_trans)
                              apply (rule_tac ep=ep in receiveIPC_simple_rewrite)
                             apply (rule monadic_rewrite_bind_head)
                             apply (rule setThreadState_schact_set)
                            apply (wp getCTE_known_cap)
                         apply (rule monadic_rewrite_bind)
                           apply (rule_tac t="capTCBPtr (cteCap replyCTE)"
                                      and t'=thread
                                      in schedule_known_rewrite)
                          apply (rule monadic_rewrite_weaken[where E=True and F=True], simp)
                          apply (rule activateThread_simple_rewrite)
                         apply wp
                           apply (simp add: ct_in_state'_def)
                          apply (wp setCurThread_ct_in_state[folded st_tcb_at'_def]
                                    Arch_switchToThread_st_tcb')[2]
                        apply (simp add: catch_liftE)
                        apply (wp setEndpoint_obj_at_tcb' threadSet_st_tcb_at_state[unfolded if_bool_eq_conj])
                       apply simp
                       apply (strengthen imp_consequent)
                       apply (unfold setSchedulerAction_def)[4]
                       apply ((wp_trace setThreadState_oa_queued user_getreg_rv setThreadState_no_sch_change
                                 setThreadState_obj_at_unchanged
                                 sts_st_tcb_at'_cases
                                 emptySlot_obj_at'_not_queued
                                 emptySlot_cte_wp_at_cteCap
                                 emptySlot_cnode_caps
                                 user_getreg_inv asUser_typ_ats
                                 asUser_obj_at_not_queued asUser_obj_at' mapM_x_wp'
                                 static_imp_wp
                                | simp
                                | clarsimp simp: obj_at'_weakenE[OF _ TrueI])+)
                        apply (wp getCTE_wp' gts_imp')
                   apply (simp add: bind_assoc catch_liftE
                                    receiveIPC_def Let_def liftM_def
                                    setThreadState_runnable_simp)
                   apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_getThreadState)
                    apply (rule monadic_rewrite_assert)
                    apply (rule_tac P="inj (case_bool thread (capTCBPtr (cteCap replyCTE)))"
                                   in monadic_rewrite_gen_asm)
                    apply (rule monadic_rewrite_trans[OF _ monadic_rewrite_transverse])
                      apply (rule monadic_rewrite_weaken[where F=False and E=True], simp)
                      apply (rule isolate_thread_actions_rewrite_bind
                                  fastpath_isolate_rewrites fastpath_isolatables
                                  bool.simps setRegister_simple
                                  zipWithM_setRegister_simple
                                  thread_actions_isolatable_bind
                                  thread_actions_isolatableD[OF setCTE_isolatable]
                                  setCTE_isolatable
                              | assumption
                              | wp assert_inv)+
                    apply (simp only: )
                    apply (rule_tac P="(\<lambda>s. ksSchedulerAction s = ResumeCurrentThread)
                                          and tcb_at' thread
                                          and (cte_wp_at' (\<lambda>cte. isReplyCap (cteCap cte))
                                                      (thread + 2 ^ cte_level_bits * tcbCallerSlot)
                                                  and (\<lambda>s. \<forall>x. tcb_at' (case_bool thread (capTCBPtr (cteCap replyCTE)) x) s)
                                                  and valid_mdb')"
                                 and F=True and E=False in monadic_rewrite_weaken)
                    apply (rule monadic_rewrite_isolate_final2)
                       apply simp
                       apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_getCTE)
                        apply (rename_tac callerCTE)
                        apply (rule monadic_rewrite_assert)
                        apply (rule monadic_rewrite_symb_exec_l, wp empty_fail_getCTE)
                         apply (rule monadic_rewrite_assert)
                         apply (simp add: emptySlot_setEndpoint_pivot)
                         apply (rule monadic_rewrite_bind)
                           apply (rule monadic_rewrite_refl2)
                           apply (clarsimp simp: isSendEP_def split: Structures_H.endpoint.split)
                          apply (rule_tac Q="\<lambda>rv. (\<lambda>_. rv = callerCTE) and Q'" for Q'
                                    in monadic_rewrite_symb_exec_r, wp)
                           apply (rule monadic_rewrite_gen_asm, simp)
                           apply (rule monadic_rewrite_trans, rule monadic_rewrite_bind_head,
                                  rule_tac cte=callerCTE in emptySlot_replymaster_rewrite)
                           apply (simp add: bind_assoc o_def)
                           apply (rule monadic_rewrite_refl)
                          apply (simp add: cte_wp_at_ctes_of pred_conj_def)
                          apply (wp getCTE_ctes_wp)
                      apply (clarsimp simp: fun_eq_iff if_flip
                                      cong: if_cong)
                      apply (drule obj_at_ko_at', clarsimp)
                      apply (frule get_tcb_state_regs_ko_at')
                      apply (clarsimp simp: zip_map2 zip_same foldl_map
                                            foldl_fun_upd
                                            foldr_copy_register_tsrs
                                            isRight_case_sum
                                      cong: if_cong)
                      apply (simp add: upto_enum_def fromEnum_def
                                       enum_register toEnum_def
                                       msgRegisters_unfold
                                 cong: if_cong)
                      apply (clarsimp split: split_if)
                      apply (rule ext)
                      apply (simp add: badgeRegister_def msgInfoRegister_def
                                       ARMMachineTypes.msgInfoRegister_def
                                       ARMMachineTypes.badgeRegister_def
                                split: split_if)
                     apply simp
                    apply (clarsimp simp: cte_wp_at_ctes_of isCap_simps
                                          map_to_ctes_partial_overwrite)
                    apply (simp add: valid_mdb'_def valid_mdb_ctes_def)
                   apply simp
                   apply (simp cong: if_cong bool.case_cong
                                   | rule getCTE_wp' gts_wp' threadGet_wp
                                          getEndpoint_wp gets_wp
                                          user_getreg_wp user_getregs_wp
                                          gets_the_wp gct_wp
                         | (simp only: curDomain_def, wp)[1])+
  apply (clarsimp simp: ct_in_state'_def st_tcb_at_tcb_at')
  apply (subst tcb_at_cte_at_offset,
         erule obj_at'_weakenE[OF _ TrueI],
         simp add: tcb_cte_cases_def cte_level_bits_def tcbSlots)
  apply clarsimp
  apply (frule cte_wp_at_valid_objs_valid_cap', clarsimp+)
  apply (rule conj_commute[THEN iffD1], rule context_conjI,
         rule resolveAddressBits_functional_Some[unfolded not_None_eq, rule_format])
   apply clarsimp
  apply clarsimp
  apply (frule resolveAddressBits_functional_real_cte_at', clarsimp+)
  apply (frule real_cte_at', clarsimp)
  apply (frule cte_wp_at_valid_objs_valid_cap', clarsimp,
         clarsimp simp: isCap_simps, simp add: valid_cap_simps')
  apply (clarsimp simp: maskCapRights_def isCap_simps)
  apply (frule_tac p="p' + 2 ^ cte_level_bits * tcbCallerSlot" for p'
              in cte_wp_at_valid_objs_valid_cap', clarsimp+)
  apply (clarsimp simp: valid_cap_simps')
  apply (subst tcb_at_cte_at_offset,
         assumption, simp add: tcb_cte_cases_def cte_level_bits_def tcbSlots)
  apply (clarsimp simp: inj_case_bool cte_wp_at_ctes_of
                         length_msgRegisters
                        n_msgRegisters_def order_less_imp_le
                 split: bool.split)
  apply (fastforce simp: cte_level_bits_def tcbSlots tcb_cte_cases_def obj_at_tcbs_of st_tcb_at_tcbs_of dest!: st_tcb_at_is_Reply_imp_not_tcbQueued[rotated])+
  done

lemmas fastpath_reply_wait_ccorres_callKernel
    = monadic_rewrite_ccorres_assemble[OF fastpath_reply_wait_ccorres fastpath_callKernel_SysReplyWait_corres]

end

end
