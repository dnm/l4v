(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory Finalise_R
imports
  IpcCancel_R
  InterruptAcc_R
  Retype_R
begin

text {* Properties about empty_slot/emptySlot *}

lemma case_Null_If:
  "(case c of NullCap \<Rightarrow> a | _ \<Rightarrow> b) = (if c = NullCap then a else b)"
  by (case_tac c, simp_all)

crunch aligned'[wp]: emptySlot pspace_aligned' (simp: case_Null_If)
crunch distinct'[wp]: emptySlot pspace_distinct' (simp: case_Null_If)

lemma updateCap_cte_wp_at_cases:
  "\<lbrace>\<lambda>s. (ptr = ptr' \<longrightarrow> cte_wp_at' (P \<circ> cteCap_update (K cap)) ptr' s) \<and> (ptr \<noteq> ptr' \<longrightarrow> cte_wp_at' P ptr' s)\<rbrace>
     updateCap ptr cap
   \<lbrace>\<lambda>rv. cte_wp_at' P ptr'\<rbrace>"
  apply (clarsimp simp: valid_def)
  apply (drule updateCap_stuff)
  apply (clarsimp simp: cte_wp_at_ctes_of modify_map_def)
  done

crunch cte_wp_at'[wp]: deletedIRQHandler "cte_wp_at' P p"

lemma emptySlot_cte_wp_cap_other:
  "\<lbrace>\<lambda>s. cte_wp_at' (\<lambda>c. P (cteCap c)) p s \<and> p \<noteq> p'\<rbrace>
  emptySlot p' opt
  \<lbrace>\<lambda>rv s. cte_wp_at' (\<lambda>c. P (cteCap c)) p s\<rbrace>"
  apply (simp add: emptySlot_def case_Null_If)
  apply (rule hoare_seq_ext [OF _ getCTE_sp])
  apply (case_tac "cteCap newCTE = NullCap")
   apply simp
   apply wp
   apply simp
  apply simp
  apply (wp updateMDB_weak_cte_wp_at updateCap_cte_wp_at_cases
            opt_return_pres_lift static_imp_wp | simp add: comp_def)+
  apply (cases "p=p'", simp)
  apply simp
  done

crunch tcb_at'[wp]: deletedIRQHandler "tcb_at' t"
crunch ct[wp]: deletedIRQHandler "\<lambda>s. P (ksCurThread s)"
crunch cur_tcb'[wp]: emptySlot "cur_tcb'"
  (ignore: setObject wp: cur_tcb_lift)

crunch ksRQ[wp]: deletedIRQHandler "\<lambda>s. P (ksReadyQueues s)"
crunch obj_at'[wp]: deletedIRQHandler "obj_at' P p"

lemmas deletedIRQHandler_valid_queues[wp] =
    valid_queues_lift [OF deletedIRQHandler_obj_at'
                          deletedIRQHandler_st_tcb_at'
                          deletedIRQHandler_ksRQ]

lemma emptySlot_queues [wp]:
  "\<lbrace>Invariants_H.valid_queues\<rbrace> emptySlot sl opt \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  unfolding emptySlot_def
  by (wp opt_return_pres_lift | wpcw | wp valid_queues_lift | simp)+

crunch nosch[wp]: deletedIRQHandler "\<lambda>s. P (ksSchedulerAction s)"
crunch ksCurDomain[wp]: deletedIRQHandler "\<lambda>s. P (ksCurDomain s)"

lemma emptySlot_sch_act_wf [wp]:
  "\<lbrace>\<lambda>s. sch_act_wf (ksSchedulerAction s) s\<rbrace>
  emptySlot sl opt
  \<lbrace>\<lambda>rv s. sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  apply (simp add: emptySlot_def case_Null_If)
  apply (wp sch_act_wf_lift tcb_in_cur_domain'_lift | wpcw | simp)+
  done

lemma updateCap_valid_objs' [wp]:
  "\<lbrace>valid_objs' and valid_cap' cap\<rbrace>
  updateCap ptr cap \<lbrace>\<lambda>r. valid_objs'\<rbrace>"
  unfolding updateCap_def
  by (wp setCTE_valid_objs getCTE_wp) (clarsimp dest!: cte_at_cte_wp_atD)

lemma valid_NullCap:
  "valid_cap' NullCap = \<top>"
  by (rule ext, simp add: valid_cap'_def)

crunch valid_objs'[wp]: deletedIRQHandler "valid_objs'"

lemma emptySlot_objs [wp]:
  "\<lbrace>valid_objs'\<rbrace>
  emptySlot sl opt
  \<lbrace>\<lambda>_. valid_objs'\<rbrace>"
  unfolding emptySlot_def case_Null_If
  by (wp updateCap_valid_objs' | simp add: valid_NullCap isArchPageCap_def | wpcw)+

crunch state_refs_of'[wp]: setInterruptState "\<lambda>s. P (state_refs_of' s)"
  (simp: state_refs_of'_pspaceI)
crunch state_refs_of'[wp]: emptySlot "\<lambda>s. P (state_refs_of' s)"
  (wp: crunch_wps)

lemma mdb_chunked2D:
  "\<lbrakk> mdb_chunked m; m \<turnstile> p \<leadsto> p'; m \<turnstile> p' \<leadsto> p'';
     m p = Some (CTE cap nd); m p'' = Some (CTE cap'' nd'');
     sameRegionAs cap cap''; p \<noteq> p'' \<rbrakk>
     \<Longrightarrow> \<exists>cap' nd'. m p' = Some (CTE cap' nd') \<and> sameRegionAs cap cap'"
  apply (subgoal_tac "\<exists>cap' nd'. m p' = Some (CTE cap' nd')")
   apply (clarsimp simp add: mdb_chunked_def)
   apply (drule spec[where x=p])
   apply (drule spec[where x=p''])
   apply clarsimp
   apply (drule mp, erule trancl_into_trancl2)
    apply (erule trancl.intros(1))
   apply (simp add: is_chunk_def)
   apply (drule spec, drule mp, erule trancl.intros(1))
   apply (drule mp, rule trancl_into_rtrancl)
    apply (erule trancl.intros(1))
   apply clarsimp
  apply (clarsimp simp: mdb_next_unfold)
  apply (case_tac z, simp)
  done

lemma nullPointer_eq_0_simp[simp]:
  "(nullPointer = 0) = True"
  "(0 = nullPointer) = True"
  by (simp add: nullPointer_def)+

lemma capRange_Null [simp]:
  "capRange NullCap = {}"
  by (simp add: capRange_def)

lemma no_0_no_0_lhs_trancl [simp]:
  "no_0 m \<Longrightarrow> \<not> m \<turnstile> 0 \<leadsto>\<^sup>+ x"
  by (rule, drule tranclD, clarsimp simp: next_unfold')
  
lemma no_0_no_0_lhs_rtrancl [simp]:
  "\<lbrakk> no_0 m; x \<noteq> 0 \<rbrakk> \<Longrightarrow> \<not> m \<turnstile> 0 \<leadsto>\<^sup>* x"
  by (clarsimp dest!: rtranclD)


locale mdb_empty = 
  mdb_ptr: mdb_ptr m _ _ slot s_cap s_node
    for m slot s_cap s_node +

  fixes n
  defines "n \<equiv>
           modify_map
             (modify_map
               (modify_map
                 (modify_map m (mdbPrev s_node)
                   (cteMDBNode_update (mdbNext_update (%_. (mdbNext s_node)))))
                 (mdbNext s_node)
                 (cteMDBNode_update
                   (\<lambda>mdb. mdbFirstBadged_update (%_. (mdbFirstBadged mdb \<or> mdbFirstBadged s_node))
                           (mdbPrev_update (%_. (mdbPrev s_node)) mdb))))
               slot (cteCap_update (%_. capability.NullCap)))
              slot (cteMDBNode_update (const nullMDBNode))"
begin

lemmas m_slot_prev = m_p_prev
lemmas m_slot_next = m_p_next
lemmas prev_slot_next = prev_p_next
lemmas next_slot_prev = next_p_prev

lemma n_revokable:
  "n p = Some (CTE cap node) \<Longrightarrow> 
  (\<exists>cap' node'. m p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then \<not> mdbRevocable node 
               else mdbRevocable node = mdbRevocable node'))"
  by (auto simp add: n_def modify_map_if nullMDBNode_def split: split_if_asm)

lemma m_revokable:
  "m p = Some (CTE cap node) \<Longrightarrow> 
  (\<exists>cap' node'. n p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then \<not> mdbRevocable node' 
               else mdbRevocable node' = mdbRevocable node))"
  apply (clarsimp simp add: n_def modify_map_if nullMDBNode_def split: split_if_asm)
  apply (cases "p=slot", simp)
  apply (cases "p=mdbNext s_node", simp)
   apply (cases "p=mdbPrev s_node", simp)
   apply clarsimp
  apply simp
  apply (cases "p=mdbPrev s_node", simp)
  apply simp
  done

lemma no_0_n:
  "no_0 n"
  using no_0 by (simp add: n_def)

lemma n_next:
  "n p = Some (CTE cap node) \<Longrightarrow> 
  (\<exists>cap' node'. m p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then mdbNext node = 0
               else if p = mdbPrev s_node 
               then mdbNext node = mdbNext s_node
               else mdbNext node = mdbNext node'))"
  apply (subgoal_tac "p \<noteq> 0")
   prefer 2
   apply (insert no_0_n)[1]
   apply clarsimp
  apply (cases "p = slot")
   apply (clarsimp simp: n_def modify_map_if initMDBNode_def split: split_if_asm)
  apply (cases "p = mdbPrev s_node")
   apply (auto simp: n_def modify_map_if initMDBNode_def split: split_if_asm)
  done
     
lemma n_prev:
  "n p = Some (CTE cap node) \<Longrightarrow> 
  (\<exists>cap' node'. m p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then mdbPrev node = 0
               else if p = mdbNext s_node 
               then mdbPrev node = mdbPrev s_node
               else mdbPrev node = mdbPrev node'))"
  apply (subgoal_tac "p \<noteq> 0")
   prefer 2
   apply (insert no_0_n)[1]
   apply clarsimp
  apply (cases "p = slot")
   apply (clarsimp simp: n_def modify_map_if initMDBNode_def split: split_if_asm)
  apply (cases "p = mdbNext s_node")
   apply (auto simp: n_def modify_map_if initMDBNode_def split: split_if_asm)
  done

lemma n_cap:
  "n p = Some (CTE cap node) \<Longrightarrow> 
  \<exists>cap' node'. m p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then cap = NullCap
               else cap' = cap)"
  apply (clarsimp simp: n_def modify_map_if initMDBNode_def split: split_if_asm)
   apply (cases node)
   apply auto
  done

lemma m_cap:
  "m p = Some (CTE cap node) \<Longrightarrow> 
  \<exists>cap' node'. n p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then cap' = NullCap
               else cap' = cap)"
  apply (clarsimp simp: n_def modify_map_cases initMDBNode_def)
  apply (cases node)
  apply clarsimp
  apply (cases "p=slot", simp)
  apply clarsimp
  apply (cases "mdbNext s_node = p", simp)
   apply fastforce
  apply simp
  apply (cases "mdbPrev s_node = p", simp)
  apply fastforce
  done

lemma n_badged:
  "n p = Some (CTE cap node) \<Longrightarrow> 
  \<exists>cap' node'. m p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then \<not> mdbFirstBadged node
               else if p = mdbNext s_node 
               then mdbFirstBadged node = (mdbFirstBadged node' \<or> mdbFirstBadged s_node)
               else mdbFirstBadged node = mdbFirstBadged node')"
  apply (subgoal_tac "p \<noteq> 0")
   prefer 2
   apply (insert no_0_n)[1]
   apply clarsimp
  apply (cases "p = slot")
   apply (clarsimp simp: n_def modify_map_if initMDBNode_def split: split_if_asm)
  apply (cases "p = mdbNext s_node")
   apply (auto simp: n_def modify_map_if nullMDBNode_def split: split_if_asm)
  done

lemma m_badged:
  "m p = Some (CTE cap node) \<Longrightarrow> 
  \<exists>cap' node'. n p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then \<not> mdbFirstBadged node'
               else if p = mdbNext s_node 
               then mdbFirstBadged node' = (mdbFirstBadged node \<or> mdbFirstBadged s_node)
               else mdbFirstBadged node' = mdbFirstBadged node)"
  apply (subgoal_tac "p \<noteq> 0")
   prefer 2
   apply (insert no_0_n)[1]
   apply clarsimp
  apply (cases "p = slot")
   apply (clarsimp simp: n_def modify_map_if nullMDBNode_def split: split_if_asm)
  apply (cases "p = mdbNext s_node")
   apply (clarsimp simp: n_def modify_map_if nullMDBNode_def split: split_if_asm)
  apply clarsimp
  apply (cases "p = mdbPrev s_node")
   apply (auto simp: n_def modify_map_if initMDBNode_def  split: split_if_asm)
  done

lemmas slot = m_p

lemma m_next:
  "m p = Some (CTE cap node) \<Longrightarrow> 
  \<exists>cap' node'. n p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then mdbNext node' = 0
               else if p = mdbPrev s_node 
               then mdbNext node' = mdbNext s_node
               else mdbNext node' = mdbNext node)"
  apply (subgoal_tac "p \<noteq> 0")
   prefer 2
   apply clarsimp
  apply (cases "p = slot")
   apply (clarsimp simp: n_def modify_map_if)
  apply (cases "p = mdbPrev s_node")
   apply (simp add: n_def modify_map_if)
  apply simp
  apply (simp add: n_def modify_map_if)
  apply (cases "mdbNext s_node = p")
   apply fastforce
  apply fastforce
  done

lemma m_prev:
  "m p = Some (CTE cap node) \<Longrightarrow> 
  \<exists>cap' node'. n p = Some (CTE cap' node') \<and> 
              (if p = slot 
               then mdbPrev node' = 0
               else if p = mdbNext s_node 
               then mdbPrev node' = mdbPrev s_node
               else mdbPrev node' = mdbPrev node)"
  apply (subgoal_tac "p \<noteq> 0")
   prefer 2
   apply clarsimp
  apply (cases "p = slot")
   apply (clarsimp simp: n_def modify_map_if)
  apply (cases "p = mdbPrev s_node")
   apply (simp add: n_def modify_map_if)
  apply simp
  apply (simp add: n_def modify_map_if)
  apply (cases "mdbNext s_node = p")
   apply fastforce
  apply fastforce
  done

lemma n_nextD:
  "n \<turnstile> p \<leadsto> p' \<Longrightarrow>
  if p = slot then p' = 0
  else if p = mdbPrev s_node 
  then m \<turnstile> p \<leadsto> slot \<and> p' = mdbNext s_node
  else m \<turnstile> p \<leadsto> p'"
  apply (clarsimp simp: mdb_next_unfold split del: split_if cong: if_cong)
  apply (case_tac z)
  apply (clarsimp split del: split_if)
  apply (drule n_next)
  apply (elim exE conjE)
  apply (simp split: split_if_asm)
  apply (frule dlist_prevD [OF m_slot_prev])
  apply (clarsimp simp: mdb_next_unfold)
  done

lemma n_next_eq:
  "n \<turnstile> p \<leadsto> p' =
  (if p = slot then p' = 0
  else if p = mdbPrev s_node 
  then m \<turnstile> p \<leadsto> slot \<and> p' = mdbNext s_node
  else m \<turnstile> p \<leadsto> p')"
  apply (rule iffI)
   apply (erule n_nextD)   
  apply (clarsimp simp: mdb_next_unfold split: split_if_asm)
    apply (simp add: n_def modify_map_if slot)
   apply hypsubst_thin
   apply (case_tac z)
   apply simp
   apply (drule m_next)
   apply clarsimp
  apply (case_tac z)
  apply simp
  apply (drule m_next)
  apply clarsimp
  done

lemma n_prev_eq:
  "n \<turnstile> p \<leftarrow> p' =
  (if p' = slot then p = 0
  else if p' = mdbNext s_node 
  then m \<turnstile> slot \<leftarrow> p' \<and> p = mdbPrev s_node
  else m \<turnstile> p \<leftarrow> p')"
  apply (rule iffI)
   apply (clarsimp simp: mdb_prev_def split del: split_if cong: if_cong)
   apply (case_tac z)
   apply (clarsimp split del: split_if)
   apply (drule n_prev)
   apply (elim exE conjE)
   apply (simp split: split_if_asm)
   apply (frule dlist_nextD [OF m_slot_next])
   apply (clarsimp simp: mdb_prev_def)
  apply (clarsimp simp: mdb_prev_def split: split_if_asm)
    apply (simp add: n_def modify_map_if slot)
   apply hypsubst_thin
   apply (case_tac z)
   apply clarsimp
   apply (drule m_prev)
   apply clarsimp   
  apply (case_tac z)
  apply simp
  apply (drule m_prev)
  apply clarsimp
  done

lemma valid_dlist_n:
  "valid_dlist n" using dlist 
  apply (clarsimp simp: valid_dlist_def2 [OF no_0_n])
  apply (simp add: n_next_eq n_prev_eq m_slot_next m_slot_prev cong: if_cong)
  apply (rule conjI, clarsimp)
   apply (rule conjI, clarsimp simp: next_slot_prev prev_slot_next) 
   apply (fastforce dest!: dlist_prev_src_unique)
  apply clarsimp
  apply (rule conjI, clarsimp)
   apply (clarsimp simp: valid_dlist_def2 [OF no_0])
   apply (case_tac "mdbNext s_node = 0")
    apply simp
    apply (subgoal_tac "m \<turnstile> slot \<leadsto> c'")
     prefer 2
     apply fastforce
    apply (clarsimp simp: mdb_next_unfold slot)
   apply (frule next_slot_prev)
   apply (drule (1) dlist_prev_src_unique, simp)
   apply simp
  apply clarsimp
  apply (rule conjI, clarsimp)
   apply (fastforce dest: dlist_next_src_unique)
  apply clarsimp
  apply (rule conjI, clarsimp)
   apply (clarsimp simp: valid_dlist_def2 [OF no_0])
   apply (clarsimp simp: mdb_prev_def slot)
  apply (clarsimp simp: valid_dlist_def2 [OF no_0])
  done

lemma caps_contained_n:
  "caps_contained' n"
  using valid
  apply (clarsimp simp: valid_mdb_ctes_def caps_contained'_def)
  apply (drule n_cap)+
  apply (clarsimp split: split_if_asm)
  apply (erule disjE, clarsimp)
  apply clarsimp
  apply fastforce
  done
  
lemma chunked:
  "mdb_chunked m"
  using valid by (simp add: valid_mdb_ctes_def)

lemma valid_badges:
  "valid_badges m" 
  using valid ..

lemma valid_badges_n:
  "valid_badges n"
proof -
  from valid_badges  
  show ?thesis
    apply (simp add: valid_badges_def2)
    apply clarsimp
    apply (drule_tac p=p in n_cap)
    apply (frule n_cap)
    apply (drule n_badged)
    apply (clarsimp simp: n_next_eq)
    apply (case_tac "p=slot", simp)
    apply clarsimp
    apply (case_tac "p'=slot", simp)
    apply clarsimp
    apply (case_tac "p = mdbPrev s_node")
     apply clarsimp
     apply (insert slot)[1]
     (* using mdb_chunked to show cap in between is same as on either side *)
     apply (subgoal_tac "capMasterCap s_cap = capMasterCap cap'")
      prefer 2
      apply (thin_tac "\<forall>p. P p" for P)
      apply (drule mdb_chunked2D[OF chunked])
           apply (fastforce simp: mdb_next_unfold)
          apply assumption+
        apply (simp add: sameRegionAs_def3)
        apply (intro disjI1)
        apply (fastforce simp:isCap_simps capMasterCap_def split:capability.splits)
       apply clarsimp
      apply clarsimp
      apply (erule sameRegionAsE, auto simp: isCap_simps capMasterCap_def split:capability.splits)[1]
     (* instantiating known valid_badges on both sides to transitively
        give the link we need *)
     apply (frule_tac x="mdbPrev s_node" in spec)
     apply simp
     apply (drule spec, drule spec, drule spec,
            drule(1) mp, drule(1) mp)
     apply simp
     apply (drule_tac x=slot in spec)
     apply (drule_tac x="mdbNext s_node" in spec)
     apply simp
     apply (drule mp, simp(no_asm) add: mdb_next_unfold)
      apply simp
     apply (cases "capBadge s_cap", simp_all)[1]
    apply clarsimp
    apply (case_tac "p' = mdbNext s_node")
     apply clarsimp
     apply (frule vdlist_next_src_unique[where y=slot])
        apply (simp add: mdb_next_unfold slot)
       apply clarsimp
      apply (rule dlist)
     apply clarsimp
    apply clarsimp
    apply fastforce
    done
qed 

lemma p_not_slot:
  assumes "n \<turnstile> p \<rightarrow> p'" 
  shows "p \<noteq> slot"
  using assms
  by induct (auto simp: mdb_next_unfold n_def modify_map_if)

lemma to_slot_eq [simp]:
  "m \<turnstile> p \<leadsto> slot = (p = mdbPrev s_node \<and> p \<noteq> 0)"
  apply (rule iffI)
   apply (frule dlist_nextD0, simp)
   apply (clarsimp simp: mdb_prev_def slot mdb_next_unfold)
  apply (clarsimp intro!: prev_slot_next)
  done

lemma n_parent_of:
  "\<lbrakk> n \<turnstile> p parentOf p'; p \<noteq> slot; p' \<noteq> slot \<rbrakk> \<Longrightarrow> m \<turnstile> p parentOf p'"
  apply (clarsimp simp: parentOf_def)
  apply (case_tac cte, case_tac cte')
  apply clarsimp
  apply (frule_tac p=p in n_cap)
  apply (frule_tac p=p in n_badged)
  apply (drule_tac p=p in n_revokable)
  apply (clarsimp)
  apply (frule_tac p=p' in n_cap)
  apply (frule_tac p=p' in n_badged)
  apply (drule_tac p=p' in n_revokable)
  apply (clarsimp split: split_if_asm;
         clarsimp simp: isMDBParentOf_def isCap_simps split: split_if_asm cong: if_cong)
  done

lemma m_parent_of:
  "\<lbrakk> m \<turnstile> p parentOf p'; p \<noteq> slot; p' \<noteq> slot; p\<noteq>p'; p'\<noteq>mdbNext s_node \<rbrakk> \<Longrightarrow> n \<turnstile> p parentOf p'"
  apply (clarsimp simp add: parentOf_def)
  apply (case_tac cte, case_tac cte')
  apply clarsimp
  apply (frule_tac p=p in m_cap)
  apply (frule_tac p=p in m_badged)
  apply (drule_tac p=p in m_revokable)
  apply clarsimp
  apply (frule_tac p=p' in m_cap)
  apply (frule_tac p=p' in m_badged)
  apply (drule_tac p=p' in m_revokable)
  apply clarsimp
  apply (simp split: split_if_asm;
         clarsimp simp: isMDBParentOf_def isCap_simps split: split_if_asm cong: if_cong)
  done

lemma m_parent_of_next:
  "\<lbrakk> m \<turnstile> p parentOf mdbNext s_node; m \<turnstile> p parentOf slot; p \<noteq> slot; p\<noteq>mdbNext s_node \<rbrakk> 
  \<Longrightarrow> n \<turnstile> p parentOf mdbNext s_node"
  using slot
  apply (clarsimp simp add: parentOf_def)
  apply (case_tac cte'a, case_tac cte)
  apply clarsimp
  apply (frule_tac p=p in m_cap)
  apply (frule_tac p=p in m_badged)
  apply (drule_tac p=p in m_revokable)
  apply (frule_tac p="mdbNext s_node" in m_cap)
  apply (frule_tac p="mdbNext s_node" in m_badged)
  apply (drule_tac p="mdbNext s_node" in m_revokable)
  apply (frule_tac p="slot" in m_cap)
  apply (frule_tac p="slot" in m_badged)
  apply (drule_tac p="slot" in m_revokable)
  apply (clarsimp simp: isMDBParentOf_def isCap_simps split: split_if_asm cong: if_cong)
  done

lemma parency_n:
  assumes "n \<turnstile> p \<rightarrow> p'" 
  shows "m \<turnstile> p \<rightarrow> p' \<and> p \<noteq> slot \<and> p' \<noteq> slot" 
using assms
proof induct
  case (direct_parent c')
  moreover
  hence "p \<noteq> slot"
    by (clarsimp simp: n_next_eq)
  moreover
  from direct_parent
  have "c' \<noteq> slot"
    by (clarsimp simp add: n_next_eq split: split_if_asm)
  ultimately
  show ?case
    apply simp
    apply (simp add: n_next_eq split: split_if_asm)
     prefer 2
     apply (erule (1) subtree.direct_parent)
     apply (erule (2) n_parent_of)
    apply clarsimp
    apply (frule n_parent_of, simp, simp)
    apply (rule subtree.trans_parent[OF _ m_slot_next], simp_all)
    apply (rule subtree.direct_parent)
      apply (erule prev_slot_next)
     apply simp
    apply (clarsimp simp: parentOf_def slot)
    apply (case_tac cte'a)
    apply (case_tac ctea)
    apply clarsimp
    apply (frule(2) mdb_chunked2D [OF chunked prev_slot_next m_slot_next])
      apply (clarsimp simp: isMDBParentOf_CTE)
     apply simp
    apply (simp add: slot)
    apply (clarsimp simp add: isMDBParentOf_CTE)
    apply (insert valid_badges)
    apply (simp add: valid_badges_def2)
    apply (drule spec[where x=slot])
    apply (drule spec[where x="mdbNext s_node"])
    apply (simp add: slot m_slot_next)
    apply (insert valid_badges)
    apply (simp add: valid_badges_def2)
    apply (drule spec[where x="mdbPrev s_node"])
    apply (drule spec[where x=slot])
    apply (simp add: slot prev_slot_next)
    apply (case_tac cte, case_tac cte')
    apply (rename_tac cap'' node'')
    apply (clarsimp simp: isMDBParentOf_CTE)
    apply (frule n_cap, drule n_badged)
    apply (frule n_cap, drule n_badged)
    apply clarsimp
    apply (case_tac cap'', simp_all add: isCap_simps)[1]
     apply (clarsimp simp: sameRegionAs_def3 isCap_simps)
    apply (clarsimp simp: sameRegionAs_def3 isCap_simps)
    done
next
  case (trans_parent c c')
  moreover
  hence "p \<noteq> slot"
    by (clarsimp simp: n_next_eq)
  moreover
  from trans_parent
  have "c' \<noteq> slot"
    by (clarsimp simp add: n_next_eq split: split_if_asm)
  ultimately
  show ?case
    apply clarsimp
    apply (simp add: n_next_eq split: split_if_asm)
     prefer 2
     apply (erule (2) subtree.trans_parent)
     apply (erule n_parent_of, simp, simp)
    apply clarsimp
    apply (rule subtree.trans_parent)
       apply (rule subtree.trans_parent, assumption)
         apply (rule prev_slot_next)
         apply clarsimp
        apply clarsimp
       apply (frule n_parent_of, simp, simp)
       apply (clarsimp simp: parentOf_def slot)
       apply (case_tac cte'a)
       apply (rename_tac cap node)
       apply (case_tac ctea)
       apply clarsimp
       apply (subgoal_tac "sameRegionAs cap s_cap")
        prefer 2
        apply (insert chunked)[1]
        apply (simp add: mdb_chunked_def)
        apply (erule_tac x="p" in allE)
        apply (erule_tac x="mdbNext s_node" in allE)
        apply simp
        apply (drule isMDBParent_sameRegion)+
        apply clarsimp
        apply (subgoal_tac "m \<turnstile> p \<leadsto>\<^sup>+ slot")
         prefer 2
         apply (rule trancl_trans)
          apply (erule subtree_mdb_next)
         apply (rule r_into_trancl)
         apply (rule prev_slot_next)
         apply clarsimp
        apply (subgoal_tac "m \<turnstile> p \<leadsto>\<^sup>+ mdbNext s_node")         
         prefer 2
         apply (erule trancl_trans)
         apply fastforce
        apply simp
        apply (erule impE)
         apply clarsimp
        apply clarsimp
        apply (thin_tac "s \<longrightarrow> t" for s t)
        apply (simp add: is_chunk_def)
        apply (erule_tac x=slot in allE)
        apply (erule impE, fastforce)
        apply (erule impE, fastforce)
        apply (clarsimp simp: slot)
       apply (clarsimp simp: isMDBParentOf_CTE)
       apply (insert valid_badges, simp add: valid_badges_def2)
       apply (drule spec[where x=slot], drule spec[where x="mdbNext s_node"])
       apply (simp add: slot m_slot_next)
       apply (case_tac cte, case_tac cte')
       apply (rename_tac cap'' node'')
       apply (clarsimp simp: isMDBParentOf_CTE)
       apply (frule n_cap, drule n_badged)
       apply (frule n_cap, drule n_badged)
       apply (clarsimp split: split_if_asm)
        apply (drule subtree_mdb_next)
        apply (drule no_loops_tranclE[OF no_loops])
        apply (erule notE, rule trancl_into_rtrancl)
        apply (rule trancl.intros(2)[OF _ m_slot_next])
        apply (rule trancl.intros(1), rule prev_slot_next)
        apply simp
       apply (case_tac cap'', simp_all add: isCap_simps)[1]
        apply (clarsimp simp: sameRegionAs_def3 isCap_simps)
       apply (clarsimp simp: sameRegionAs_def3 isCap_simps)
      apply (rule m_slot_next)
     apply simp
    apply (erule n_parent_of, simp, simp)
    done
qed

lemma parency_m:
  assumes "m \<turnstile> p \<rightarrow> p'" 
  shows "p \<noteq> slot \<longrightarrow> (if p' \<noteq> slot then n \<turnstile> p \<rightarrow> p' else m \<turnstile> p \<rightarrow> mdbNext s_node \<longrightarrow> n \<turnstile> p \<rightarrow> mdbNext s_node)" 
using assms
proof induct
  case (direct_parent c)
  thus ?case
    apply clarsimp
    apply (rule conjI)
     apply clarsimp
     apply (rule subtree.direct_parent)
       apply (simp add: n_next_eq)
       apply clarsimp
       apply (subgoal_tac "mdbPrev s_node \<noteq> 0")
        prefer 2
        apply (clarsimp simp: mdb_next_unfold)
       apply (drule prev_slot_next)
       apply (clarsimp simp: mdb_next_unfold)
      apply assumption
     apply (erule m_parent_of, simp, simp)
      apply clarsimp
     apply clarsimp
     apply (drule dlist_next_src_unique)
       apply fastforce
      apply clarsimp
     apply simp
    apply clarsimp
    apply (rule subtree.direct_parent)
      apply (simp add: n_next_eq)
     apply (drule subtree_parent)
     apply (clarsimp simp: parentOf_def)
    apply (drule subtree_parent)
    apply (erule (1) m_parent_of_next)
     apply clarsimp
    apply clarsimp
    done
next
  case (trans_parent c c')
  thus ?case
    apply clarsimp
    apply (rule conjI)
     apply clarsimp
     apply (cases "c=slot")
      apply simp
      apply (erule impE)
       apply (erule subtree.trans_parent)
         apply fastforce
        apply (clarsimp simp: slot mdb_next_unfold)
       apply (clarsimp simp: slot mdb_next_unfold)
      apply (clarsimp simp: slot mdb_next_unfold)
     apply clarsimp
     apply (erule subtree.trans_parent)
       apply (simp add: n_next_eq)
       apply clarsimp
       apply (subgoal_tac "mdbPrev s_node \<noteq> 0")
        prefer 2
        apply (clarsimp simp: mdb_next_unfold)
       apply (drule prev_slot_next)
       apply (clarsimp simp: mdb_next_unfold)
      apply assumption
     apply (erule m_parent_of, simp, simp)
      apply clarsimp
      apply (drule subtree_mdb_next)
      apply (drule trancl_trans)
       apply (erule r_into_trancl)
      apply simp
     apply clarsimp
     apply (drule dlist_next_src_unique)
       apply fastforce
      apply clarsimp
     apply simp
    apply clarsimp
    apply (erule subtree.trans_parent)
      apply (simp add: n_next_eq)
     apply clarsimp
    apply (rule m_parent_of_next, erule subtree_parent, assumption, assumption)
    apply clarsimp
    done
qed

lemma parency:
  "n \<turnstile> p \<rightarrow> p' = (p \<noteq> slot \<and> p' \<noteq> slot \<and> m \<turnstile> p \<rightarrow> p')"
  by (auto dest!: parency_n parency_m)

lemma descendants:
  "descendants_of' p n = 
  (if p = slot then {} else descendants_of' p m - {slot})"
  by (auto simp add: parency descendants_of'_def)

lemma n_tranclD:
  "n \<turnstile> p \<leadsto>\<^sup>+ p' \<Longrightarrow> m \<turnstile> p \<leadsto>\<^sup>+ p' \<and> p' \<noteq> slot"
  apply (erule trancl_induct)
   apply (clarsimp simp add: n_next_eq split: split_if_asm)
     apply (rule mdb_chain_0D)
      apply (rule chain)
     apply (clarsimp simp: slot)
    apply (blast intro: trancl_trans prev_slot_next)
   apply fastforce
  apply (clarsimp simp: n_next_eq split: split_if_asm)
   apply (erule trancl_trans)
   apply (blast intro: trancl_trans prev_slot_next)
  apply (fastforce intro: trancl_trans)
  done
  
lemma m_tranclD:
  "m \<turnstile> p \<leadsto>\<^sup>+ p' \<Longrightarrow> 
  if p = slot then n \<turnstile> mdbNext s_node \<leadsto>\<^sup>* p'
  else if p' = slot then n \<turnstile> p \<leadsto>\<^sup>+ mdbNext s_node
  else n \<turnstile> p \<leadsto>\<^sup>+ p'"
  using no_0_n
  apply -
  apply (erule trancl_induct)
   apply clarsimp
   apply (rule conjI)
    apply clarsimp
    apply (rule r_into_trancl)
    apply (clarsimp simp: n_next_eq)
   apply clarsimp
   apply (rule conjI)
    apply (insert m_slot_next)[1]
    apply (clarsimp simp: mdb_next_unfold)
   apply clarsimp
   apply (rule r_into_trancl)
   apply (clarsimp simp: n_next_eq)
   apply (rule context_conjI)
    apply (clarsimp simp: mdb_next_unfold)
   apply (drule prev_slot_next)
   apply (clarsimp simp: mdb_next_unfold)
  apply clarsimp
  apply (rule conjI)
   apply clarsimp
   apply (rule conjI)
    apply clarsimp
    apply (drule prev_slot_next)
    apply (drule trancl_trans, erule r_into_trancl)
    apply simp
   apply clarsimp
   apply (erule trancl_trans)
   apply (rule r_into_trancl)
   apply (simp add: n_next_eq)
  apply clarsimp
  apply (rule conjI)
   apply clarsimp
   apply (erule rtrancl_trans)
   apply (rule r_into_rtrancl)
   apply (simp add: n_next_eq)
   apply (rule conjI)
    apply clarsimp
    apply (rule context_conjI)
     apply (clarsimp simp: mdb_next_unfold)
    apply (drule prev_slot_next)
    apply (clarsimp simp: mdb_next_unfold)
   apply clarsimp
  apply clarsimp
  apply (simp split: split_if_asm)
   apply (clarsimp simp: mdb_next_unfold slot)
  apply (erule trancl_trans)
  apply (rule r_into_trancl)
  apply (clarsimp simp add: n_next_eq)
  apply (rule context_conjI)
   apply (clarsimp simp: mdb_next_unfold)
  apply (drule prev_slot_next)
  apply (clarsimp simp: mdb_next_unfold)
  done
   
lemma n_trancl_eq:
  "n \<turnstile> p \<leadsto>\<^sup>+ p' = (m \<turnstile> p \<leadsto>\<^sup>+ p' \<and> (p = slot \<longrightarrow> p' = 0) \<and> p' \<noteq> slot)"
  using no_0_n
  apply -
  apply (rule iffI)
   apply (frule n_tranclD)
   apply clarsimp
   apply (drule tranclD)
   apply (clarsimp simp: n_next_eq)
   apply (simp add: rtrancl_eq_or_trancl)
  apply clarsimp
  apply (drule m_tranclD)
  apply (simp split: split_if_asm)
  apply (rule r_into_trancl)
  apply (simp add: n_next_eq)
  done

lemma n_rtrancl_eq:
  "n \<turnstile> p \<leadsto>\<^sup>* p' = 
  (m \<turnstile> p \<leadsto>\<^sup>* p' \<and> 
   (p = slot \<longrightarrow> p' = 0 \<or> p' = slot) \<and> 
   (p' = slot \<longrightarrow> p = slot))"
  by (auto simp: rtrancl_eq_or_trancl n_trancl_eq)

lemma mdb_chain_0_n:
  "mdb_chain_0 n"
  using chain
  apply (clarsimp simp: mdb_chain_0_def)
  apply (drule bspec)
   apply (fastforce simp: n_def modify_map_if split: split_if_asm)
  apply (simp add: n_trancl_eq)
  done

lemma mdb_chunked_n:
  "mdb_chunked n"
  using chunked
  apply (clarsimp simp: mdb_chunked_def)
  apply (drule n_cap)+
  apply (clarsimp split: split_if_asm)
  apply (case_tac "p=slot", clarsimp)
  apply clarsimp
  apply (erule_tac x=p in allE)
  apply (erule_tac x=p' in allE)
  apply (clarsimp simp: is_chunk_def)
  apply (simp add: n_trancl_eq n_rtrancl_eq)
  apply (rule conjI) 
   apply clarsimp
   apply (erule_tac x=p'' in allE)
   apply clarsimp
   apply (drule_tac p=p'' in m_cap)
   apply clarsimp
  apply clarsimp
  apply (erule_tac x=p'' in allE)
  apply clarsimp
  apply (drule_tac p=p'' in m_cap)
  apply clarsimp
  done

lemma untyped_mdb_n:
  "untyped_mdb' n"
  using untyped_mdb
  apply (simp add: untyped_mdb'_def descendants_of'_def parency)
  apply clarsimp 
  apply (drule n_cap)+
  apply (clarsimp split: split_if_asm)
  apply (case_tac "p=slot", simp)
  apply clarsimp
  done

lemma untyped_inc_n:
  "untyped_inc' n"
  using untyped_inc
  apply (simp add: untyped_inc'_def descendants_of'_def parency)
  apply clarsimp 
  apply (drule n_cap)+
  apply (clarsimp split: split_if_asm)
  apply (case_tac "p=slot", simp)
  apply clarsimp
  apply (erule_tac x=p in allE)
  apply (erule_tac x=p' in allE)
  apply simp
  done

lemmas vn_prev [dest!] = valid_nullcaps_prev [OF _ slot no_0 dlist nullcaps]
lemmas vn_next [dest!] = valid_nullcaps_next [OF _ slot no_0 dlist nullcaps]

lemma nullcaps_n: "valid_nullcaps n"
proof -
  from valid have "valid_nullcaps m" ..
  thus ?thesis
    apply (clarsimp simp: valid_nullcaps_def nullMDBNode_def nullPointer_def)
    apply (frule n_cap)
    apply (frule n_next)
    apply (frule n_badged)
    apply (frule n_revokable)
    apply (drule n_prev)
    apply (case_tac n)
    apply (insert slot)
    apply (fastforce split: split_if_asm)
    done 
qed

lemma ut_rev_n: "ut_revocable' n"
  apply(insert valid)
  apply(clarsimp simp: ut_revocable'_def)
  apply(frule n_cap)
  apply(drule n_revokable)
  apply(clarsimp simp: isCap_simps split: split_if_asm)
  apply(simp add: valid_mdb_ctes_def ut_revocable'_def)
  apply(clarsimp simp: isUntypedCap_def)
  done

lemma class_links_n: "class_links n"
  using valid slot
  apply (clarsimp simp: valid_mdb_ctes_def class_links_def)
  apply (case_tac cte, case_tac cte')
  apply (drule n_nextD)
  apply (clarsimp simp: split: split_if_asm)
    apply (simp add: no_0_n)
   apply (drule n_cap)+
   apply clarsimp
   apply (frule spec[where x=slot],
          drule spec[where x="mdbNext s_node"],
          simp, simp add: m_slot_next)
   apply (drule spec[where x="mdbPrev s_node"],
          drule spec[where x=slot], simp)
  apply (drule n_cap)+
  apply clarsimp
  apply (fastforce split: split_if_asm)
  done

lemma distinct_zombies_m: "distinct_zombies m"
  using valid by (simp add: valid_mdb_ctes_def)

lemma distinct_zombies_n[simp]:
  "distinct_zombies n"
  using distinct_zombies_m
  apply (simp add: n_def distinct_zombies_nonCTE_modify_map)
  apply (subst modify_map_apply[where p=slot])
   apply (simp add: modify_map_def slot)
  apply simp
  apply (rule distinct_zombies_sameMasterE)
    apply (simp add: distinct_zombies_nonCTE_modify_map)
   apply (simp add: modify_map_def slot)
  apply simp
  done

lemma irq_control_n [simp]: "irq_control n"
  using slot
  apply (clarsimp simp: irq_control_def)
  apply (frule n_revokable)
  apply (drule n_cap)
  apply (clarsimp split: split_if_asm)
  apply (frule irq_revocable, rule irq_control)
  apply clarsimp
  apply (drule n_cap)
  apply (clarsimp simp: split_if_asm)
  apply (erule (1) irq_controlD, rule irq_control)
  done

lemma reply_masters_rvk_fb_m: "reply_masters_rvk_fb m"
  using valid by auto

lemma reply_masters_rvk_fb_n [simp]: "reply_masters_rvk_fb n"
  using reply_masters_rvk_fb_m
  apply (simp add: reply_masters_rvk_fb_def n_def
                   ball_ran_modify_map_eq
                   modify_map_comp[symmetric])
  apply (subst ball_ran_modify_map_eq)
   apply (frule bspec, rule ranI, rule slot)
   apply (simp add: nullMDBNode_def isCap_simps modify_map_def
                    slot)
  apply (subst ball_ran_modify_map_eq)
   apply (clarsimp simp add: modify_map_def)
   apply fastforce
  apply (simp add: ball_ran_modify_map_eq)
  done  

lemma vmdb_n: "valid_mdb_ctes n"
  by (simp add: valid_mdb_ctes_def valid_dlist_n
                no_0_n mdb_chain_0_n valid_badges_n
                caps_contained_n mdb_chunked_n
                untyped_mdb_n untyped_inc_n
                nullcaps_n ut_rev_n class_links_n)

end

crunch ctes_of[wp]: deletedIRQHandler "\<lambda>s. P (ctes_of s)"

lemma emptySlot_mdb [wp]:
  "\<lbrace>valid_mdb'\<rbrace> 
  emptySlot sl opt
  \<lbrace>\<lambda>_. valid_mdb'\<rbrace>" 
  unfolding emptySlot_def valid_mdb'_def 
  apply (simp only: case_Null_If)
  apply (wp updateCap_ctes_of_wp getCTE_wp'
            opt_return_pres_lift)
  apply (clarsimp)
  apply (case_tac cte)
  apply (rename_tac cap node)
  apply (simp)
  apply (subgoal_tac "mdb_empty (ctes_of s) sl cap node")
   prefer 2
   apply (rule mdb_empty.intro)
   apply (rule mdb_ptr.intro)
    apply (rule vmdb.intro)
    apply (simp add: valid_mdb_ctes_def)
   apply (rule mdb_ptr_axioms.intro)
   apply (simp add: cte_wp_at_ctes_of)
  apply (rule conjI, clarsimp simp: valid_mdb_ctes_def)
  apply (erule mdb_empty.vmdb_n[unfolded const_def])
  done

lemma if_live_then_nonz_cap'_def2:
  "if_live_then_nonz_cap' = (\<lambda>s. \<forall>ptr. ko_wp_at' live' ptr s
                               \<longrightarrow> (\<exists>p c. cteCaps_of s p = Some c \<and> ptr \<in> zobj_refs' c))"
  by (fastforce intro!: ext
                 simp: if_live_then_nonz_cap'_def ex_nonz_cap_to'_def
                       cte_wp_at_ctes_of cteCaps_of_def)

lemma updateMDB_ko_wp_at_live[wp]:
  "\<lbrace>\<lambda>s. P (ko_wp_at' live' p' s)\<rbrace>
      updateMDB p m
   \<lbrace>\<lambda>rv s. P (ko_wp_at' live' p' s)\<rbrace>"
  unfolding updateMDB_def Let_def
  apply (rule hoare_pre, wp)
  apply simp
  done

lemma updateCap_ko_wp_at_live[wp]:
  "\<lbrace>\<lambda>s. P (ko_wp_at' live' p' s)\<rbrace>
      updateCap p cap
   \<lbrace>\<lambda>rv s. P (ko_wp_at' live' p' s)\<rbrace>"
  unfolding updateCap_def
  by wp

primrec
  threadCapRefs :: "capability \<Rightarrow> word32 set"
where
  "threadCapRefs (ThreadCap r)                  = {r}"
| "threadCapRefs (ReplyCap t m)                 = {}"
| "threadCapRefs NullCap                        = {}"
| "threadCapRefs (UntypedCap r n i)             = {}"
| "threadCapRefs (EndpointCap r badge x y z)    = {}"
| "threadCapRefs (AsyncEndpointCap r badge x y) = {}"
| "threadCapRefs (CNodeCap r b g gsz)           = {}"
| "threadCapRefs (Zombie r b n)                 = {}"
| "threadCapRefs (ArchObjectCap ac)             = {}"
| "threadCapRefs (IRQHandlerCap irq)            = {}"
| "threadCapRefs (IRQControlCap)                = {}"
| "threadCapRefs (DomainCap)                    = {}"

lemma threadCapRefs_def2:
  "threadCapRefs cap = (case cap of ThreadCap r \<Rightarrow> {r} | _ \<Rightarrow> {})"
  by (simp split: capability.split)

definition
  "isFinal cap p m \<equiv> 
  \<not>isUntypedCap cap \<and>
  (\<forall>p' c. m p' = Some c \<longrightarrow>
          p \<noteq> p' \<longrightarrow> \<not>isUntypedCap c \<longrightarrow>
          \<not> sameObjectAs cap c)"

lemma not_FinalE:
  "\<lbrakk> \<not> isFinal cap sl cps; isUntypedCap cap \<Longrightarrow> P;
     \<And>p c. \<lbrakk> cps p = Some c; p \<noteq> sl; \<not> isUntypedCap c; sameObjectAs cap c \<rbrakk> \<Longrightarrow> P
    \<rbrakk> \<Longrightarrow> P"
  by (fastforce simp: isFinal_def)

definition
 "removeable' sl \<equiv> \<lambda>s cap.
    (\<exists>p. p \<noteq> sl \<and> cte_wp_at' (\<lambda>cte. capMasterCap (cteCap cte) = capMasterCap cap) p s)
    \<or> ((\<forall>p \<in> cte_refs' cap (irq_node' s). p \<noteq> sl \<longrightarrow> cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) p s)
         \<and> (\<forall>p \<in> zobj_refs' cap. ko_wp_at' (Not \<circ> live') p s)
         \<and> (\<forall>t \<in> threadCapRefs cap. \<forall>p. t \<notin> set (ksReadyQueues s p)))"

lemma not_Final_removeable:
  "\<not> isFinal cap sl (cteCaps_of s)
    \<Longrightarrow> removeable' sl s cap"
  apply (erule not_FinalE)
   apply (clarsimp simp: removeable'_def isCap_simps)
  apply (clarsimp simp: cteCaps_of_def sameObjectAs_def2 removeable'_def
                        cte_wp_at_ctes_of)
  apply fastforce
  done

crunch ko_wp_at'[wp]: deletedIRQHandler "\<lambda>s. P (ko_wp_at' P' p s)"
crunch cteCaps_of[wp]: deletedIRQHandler "\<lambda>s. P (cteCaps_of s)"
  (simp: cteCaps_of_def o_def)

lemma emptySlot_iflive'[wp]:
  "\<lbrace>\<lambda>s. if_live_then_nonz_cap' s \<and> cte_wp_at' (\<lambda>cte. removeable' sl s (cteCap cte)) sl s\<rbrace>
     emptySlot sl opt
   \<lbrace>\<lambda>rv. if_live_then_nonz_cap'\<rbrace>"
  apply (simp add: emptySlot_def case_Null_If if_live_then_nonz_cap'_def2)
  apply (rule hoare_pre)
   apply (simp only: imp_conv_disj)
   apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift
             getCTE_wp' opt_return_pres_lift)
  apply clarsimp
  apply (drule spec, drule(1) mp)
  apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (case_tac "p \<noteq> sl")
   apply (rule_tac x=p in exI)
   apply (clarsimp simp: modify_map_def)
  apply (simp add: removeable'_def cteCaps_of_def)
  apply (erule disjE)
   apply (clarsimp simp: cte_wp_at_ctes_of modify_map_def
                  dest!: capMaster_same_refs)
   apply fastforce
  apply clarsimp
  apply (drule(1) bspec)
  apply (clarsimp simp: ko_wp_at'_def)
  done

crunch irq_node'[wp]: doMachineOp "\<lambda>s. P (irq_node' s)"

lemma setIRQState_irq_node'[wp]:
  "\<lbrace>\<lambda>s. P (irq_node' s)\<rbrace> setIRQState state irq \<lbrace>\<lambda>_ s. P (irq_node' s)\<rbrace>"
  apply (simp add: setIRQState_def setInterruptState_def getInterruptState_def)
  apply wp
  apply simp
  done

crunch irq_node'[wp]: emptySlot "\<lambda>s. P (irq_node' s)"

lemma emptySlot_ifunsafe'[wp]:
  "\<lbrace>\<lambda>s. if_unsafe_then_cap' s \<and> cte_wp_at' (\<lambda>cte. removeable' sl s (cteCap cte)) sl s\<rbrace>
     emptySlot sl opt
   \<lbrace>\<lambda>rv. if_unsafe_then_cap'\<rbrace>"
  apply (simp add: ifunsafe'_def3)
  apply (rule hoare_pre, rule hoare_use_eq_irq_node'[OF emptySlot_irq_node'])
   apply (simp add: emptySlot_def case_Null_If)
   apply (wp opt_return_pres_lift | simp add: o_def)+
   apply (wp getCTE_cteCap_wp)
  apply (clarsimp simp: tree_cte_cteCap_eq[unfolded o_def]
                 split: option.split_asm split_if_asm
                 dest!: modify_map_K_D)
  apply (drule_tac x=cref in spec, clarsimp)
  apply (case_tac "cref' \<noteq> sl")
   apply (rule_tac x=cref' in exI)
   apply (clarsimp simp: modify_map_def)
  apply (simp add: removeable'_def)
  apply (erule disjE)
   apply (clarsimp simp: modify_map_def)
   apply (subst(asm) tree_cte_cteCap_eq[unfolded o_def])
   apply (clarsimp split: option.split_asm dest!: capMaster_same_refs)
   apply fastforce
  apply clarsimp
  apply (drule(1) bspec)
  apply (clarsimp simp: cte_wp_at_ctes_of cteCaps_of_def)
  done

lemma ex_nonz_cap_to'_def2:
  "ex_nonz_cap_to' p = (\<lambda>s. \<exists>p' c. cteCaps_of s p' = Some c \<and> p \<in> zobj_refs' c)"
  by (fastforce simp: ex_nonz_cap_to'_def cte_wp_at_ctes_of cteCaps_of_def
             intro!: ext)

lemma ctes_of_valid'[elim]:
  "\<lbrakk>ctes_of s p = Some cte; valid_objs' s\<rbrakk> \<Longrightarrow> s \<turnstile>' cteCap cte"
  by (cases cte, simp) (rule ctes_of_valid_cap')

crunch ksrq[wp]: deletedIRQHandler "\<lambda>s. P (ksReadyQueues s)"

crunch valid_idle'[wp]: setInterruptState "valid_idle'"
  (simp: valid_idle'_def)
crunch valid_idle'[wp]: deletedIRQHandler "valid_idle'"

lemma emptySlot_idle'[wp]:
  "\<lbrace>\<lambda>s. valid_idle' s \<and> cte_wp_at' (\<lambda>cte. removeable' sl s (cteCap cte)) sl s\<rbrace>
     emptySlot sl opt
   \<lbrace>\<lambda>rv. valid_idle'\<rbrace>"
  apply (simp add: emptySlot_def case_Null_If ifunsafe'_def3)
  apply (rule hoare_pre)
   apply (wp updateCap_idle' opt_return_pres_lift
                | simp only: o_def capRange_Null mem_simps
                | simp)+
  done

crunch ksArch[wp]: emptySlot "\<lambda>s. P (ksArchState s)"
crunch ksIdle[wp]: emptySlot "\<lambda>s. P (ksIdleThread s)"

lemma valid_refs'_cteCaps:
  "valid_refs' S (ctes_of s) = (\<forall>c \<in> ran (cteCaps_of s). S \<inter> capRange c = {})"
  apply (simp add: valid_refs'_def cteCaps_of_def)
  apply (fastforce elim!: ranE)
  done

lemma emptySlot_cteCaps_of:
  "\<lbrace>\<lambda>s. P (cteCaps_of s(p \<mapsto> NullCap))\<rbrace>
     emptySlot p opt
   \<lbrace>\<lambda>rv s. P (cteCaps_of s)\<rbrace>"
  apply (simp add: emptySlot_def case_Null_If)
  apply (wp opt_return_pres_lift)
  apply (rule hoare_strengthen_post [OF getCTE_sp])
  apply (clarsimp simp: cteCaps_of_def cte_wp_at_ctes_of)
  apply (auto elim!: rsubst[where P=P]
               simp: modify_map_def fun_upd_def[symmetric] o_def
                     fun_upd_idem)
  done

lemma emptySlot_valid_global_refs[wp]:
  "\<lbrace>valid_global_refs'\<rbrace> emptySlot sl opt \<lbrace>\<lambda>rv. valid_global_refs'\<rbrace>"
  apply (simp add: valid_global_refs'_def global_refs'_def)
  apply (rule hoare_pre)
   apply (rule hoare_use_eq_irq_node' [OF emptySlot_irq_node'])
   apply (rule hoare_use_eq [where f=ksArchState, OF emptySlot_ksArch])
   apply (rule hoare_use_eq [where f=ksIdleThread, OF emptySlot_ksIdle])
   apply (simp add: valid_refs'_cteCaps)
   apply (rule emptySlot_cteCaps_of)
  apply (clarsimp simp: valid_refs'_cteCaps elim!: ranE
                 split: split_if_asm)
  apply fastforce
  done

lemmas doMachineOp_irq_handlers[wp]
    = valid_irq_handlers_lift'' [OF doMachineOp_ctes_of doMachineOp_ksInterruptState]

lemma deletedIRQHandler_irq_handlers'[wp]:
  "\<lbrace>\<lambda>s. valid_irq_handlers' s \<and> (IRQHandlerCap irq \<notin> ran (cteCaps_of s))\<rbrace>
       deletedIRQHandler irq
   \<lbrace>\<lambda>rv. valid_irq_handlers'\<rbrace>"
  apply (simp add: deletedIRQHandler_def setIRQState_def)
  apply wp
   apply (simp_all add: setInterruptState_def getInterruptState_def)
   apply wp
  apply (clarsimp simp: valid_irq_handlers'_def irq_issued'_def ran_def cteCaps_of_def)
  done

lemma emptySlot_valid_irq_handlers'[wp]:
  "\<lbrace>\<lambda>s. valid_irq_handlers' s
          \<and> (\<forall>irq sl'. opt = Some irq \<longrightarrow> sl' \<noteq> sl \<longrightarrow> cteCaps_of s sl' \<noteq> Some (IRQHandlerCap irq))\<rbrace>
     emptySlot sl opt
   \<lbrace>\<lambda>rv. valid_irq_handlers'\<rbrace>"
  apply (simp add: emptySlot_def case_Null_If)
  apply (wp | wpc)+
       apply (unfold valid_irq_handlers'_def irq_issued'_def)
       apply (wp getCTE_wp)
  apply (clarsimp simp: cteCaps_of_def cte_wp_at_ctes_of ran_def modify_map_def)
  apply auto
  done

(* Levity: added (20090126 19:32:20) *)
declare setIRQState_irq_states' [wp]

crunch irq_states' [wp]: emptySlot valid_irq_states'

crunch no_0_obj' [wp]: emptySlot no_0_obj'
 (wp: crunch_wps)

crunch valid_queues'[wp]: setInterruptState "valid_queues'"
  (simp: valid_queues'_def)

crunch valid_queues'[wp]: emptySlot "valid_queues'"

crunch pde_mappings'[wp]: emptySlot "valid_pde_mappings'"

lemma deletedIRQHandler_irqs_masked'[wp]:
  "\<lbrace>irqs_masked'\<rbrace> deletedIRQHandler irq \<lbrace>\<lambda>_. irqs_masked'\<rbrace>"
  apply (simp add: deletedIRQHandler_def setIRQState_def getInterruptState_def setInterruptState_def)
  apply (wp dmo_maskInterrupt)
  apply (simp add: irqs_masked'_def)
  done

crunch irqs_masked'[wp]: emptySlot "irqs_masked'"

lemma setIRQState_umm:
 "\<lbrace>\<lambda>s. P (underlying_memory (ksMachineState s))\<rbrace>
   setIRQState irqState irq
  \<lbrace>\<lambda>_ s. P (underlying_memory (ksMachineState s))\<rbrace>"
  by (simp add: setIRQState_def maskInterrupt_def
                setInterruptState_def getInterruptState_def
      | wp dmo_lift')+

crunch umm[wp]: emptySlot "\<lambda>s. P (underlying_memory (ksMachineState s))"
  (wp: setIRQState_umm)

lemma emptySlot_vms'[wp]:
  "\<lbrace>valid_machine_state'\<rbrace> emptySlot slot irq \<lbrace>\<lambda>_. valid_machine_state'\<rbrace>"
  by (simp add: valid_machine_state'_def pointerInUserData_def)
     (wp hoare_vcg_all_lift hoare_vcg_disj_lift)

crunch pspace_domain_valid[wp]: emptySlot "pspace_domain_valid"

lemma ct_not_inQ_ksInterruptState_update[simp]:
  "ct_not_inQ (s\<lparr>ksInterruptState := v\<rparr>) = ct_not_inQ s"
  by (simp add: ct_not_inQ_def)

crunch nosch[wp]: emptySlot "\<lambda>s. P (ksSchedulerAction s)"
crunch ct[wp]: emptySlot "\<lambda>s. P (ksCurThread s)"
crunch ksCurDomain[wp]: emptySlot "\<lambda>s. P (ksCurDomain s)"
crunch ksDomSchedule[wp]: emptySlot "\<lambda>s. P (ksDomSchedule s)"
crunch ksDomScheduleIdx[wp]: emptySlot "\<lambda>s. P (ksDomScheduleIdx s)"

lemma deletedIRQHandler_ct_not_inQ[wp]:
  "\<lbrace>ct_not_inQ\<rbrace> deletedIRQHandler irq \<lbrace>\<lambda>_. ct_not_inQ\<rbrace>"
  apply (rule ct_not_inQ_lift [OF deletedIRQHandler_nosch])
  apply (rule hoare_weaken_pre)
   apply (wps deletedIRQHandler_ct)
   apply (simp add: deletedIRQHandler_def setIRQState_def)
   apply (wp)
  apply (simp add: comp_def)
  done

lemma emptySlot_ct_not_inQ[wp]:
  "\<lbrace>ct_not_inQ\<rbrace> emptySlot sl opt \<lbrace>\<lambda>_. ct_not_inQ\<rbrace>"
  apply (simp add: emptySlot_def)
  apply (case_tac opt)
   apply (wp, wpc)
              apply (wp | clarsimp)+
   apply (rule_tac Q="\<lambda>_. ct_not_inQ" in hoare_post_imp, clarsimp)
   apply (wp, wpc)
             apply (wp | clarsimp)+
  apply (rule_tac Q="\<lambda>_. ct_not_inQ" in hoare_post_imp, clarsimp)
  apply (wp)
  done

lemma emptySlot_tcbDomain[wp]:
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t\<rbrace> emptySlot sl opt \<lbrace>\<lambda>_. obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t\<rbrace>"
apply (simp add: emptySlot_def)
apply (wp hoare_vcg_all_lift getCTE_wp | wpc | simp add: cte_wp_at'_def)+
done

lemma emptySlot_ct_idle_or_in_cur_domain'[wp]:
  "\<lbrace>ct_idle_or_in_cur_domain'\<rbrace> emptySlot sl opt \<lbrace>\<lambda>_. ct_idle_or_in_cur_domain'\<rbrace>"
apply (wp ct_idle_or_in_cur_domain'_lift2 tcb_in_cur_domain'_lift | simp)+
done

lemma emptySlot_invs'[wp]:
  "\<lbrace>\<lambda>s. invs' s \<and> cte_wp_at' (\<lambda>cte. removeable' sl s (cteCap cte)) sl s
            \<and> (\<forall>irq sl'. opt = Some irq \<longrightarrow> sl' \<noteq> sl \<longrightarrow> cteCaps_of s sl' \<noteq> Some (IRQHandlerCap irq))\<rbrace>
     emptySlot sl opt
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: invs'_def valid_state'_def valid_pspace'_def)
  apply (rule hoare_pre)
   apply (wp valid_arch_state_lift' valid_irq_node_lift)
  apply clarsimp
  done

lemma opt_deleted_irq_corres:
  "corres dc \<top> \<top>
    (case opt of None \<Rightarrow> return () | Some irq \<Rightarrow> deleted_irq_handler irq)
    (case opt of None \<Rightarrow> return () | Some irq \<Rightarrow> deletedIRQHandler irq)"
  apply (cases opt, simp_all)
  apply (simp add: deleted_irq_handler_def deletedIRQHandler_def)
  apply (rule set_irq_state_corres)
  apply (simp add: irq_state_relation_def)
  done

lemma exec_update_cdt_list:
  "\<lbrakk>\<exists>x\<in>fst (g r (s\<lparr>cdt_list := (f (cdt_list s))\<rparr>)). P x\<rbrakk>
\<Longrightarrow> \<exists>x\<in>fst (((update_cdt_list f) >>= g) (s::det_state)). P x"
  apply (clarsimp simp: update_cdt_list_def set_cdt_list_def exec_gets exec_get put_def bind_assoc)
  apply (clarsimp simp: bind_def)
  apply (erule bexI)
  apply simp
  done

lemma set_cap_trans_state:
  "((),s') \<in> fst (set_cap c p s) \<Longrightarrow> ((),trans_state f s') \<in> fst (set_cap c p (trans_state f s))"
  apply (cases p)
  apply (clarsimp simp add: set_cap_def in_monad get_object_def)
  apply (case_tac y)
  apply (auto simp add: in_monad set_object_def split: split_if_asm)
  done

lemma empty_slot_corres:
  "corres dc (einvs and cte_at slot) invs'
             (empty_slot slot opt) (emptySlot (cte_map slot) opt)"
  unfolding emptySlot_def empty_slot_def case_Null_If
  apply (rule corres_guard_imp)
    apply (rule_tac R="\<lambda>cap. einvs and cte_wp_at (op = cap) slot" and
                    R'="\<lambda>cte. invs' and cte_wp_at' (op = cte) (cte_map slot)" in 
                    corres_split [OF _ get_cap_corres])
      defer
      apply (wp get_cap_wp getCTE_wp')
    apply fastforce
   apply fastforce
  apply (rule corres_symb_exec_r)
     defer
     apply (rule hoare_return_sp)
    apply wp
   apply (rule no_fail_pre, wp)
  apply (rule corres_symb_exec_r)
     defer
     apply (rule hoare_return_sp)
    apply wp
   apply (rule no_fail_pre, wp)
  apply (rule corres_symb_exec_r)
     defer
     apply (rule hoare_return_sp)
    apply wp
   apply (rule no_fail_pre, wp)
  apply simp
  apply (rule conjI, clarsimp)
  apply clarsimp
  apply (rule conjI, clarsimp)
  apply clarsimp
  apply (simp only: bind_assoc[symmetric])
  apply (rule corres_split'[where r'=dc, OF _ opt_deleted_irq_corres])
    defer
    apply wp
  apply (rule corres_no_failI)
   apply (rule no_fail_pre, wp static_imp_wp)
   apply (clarsimp simp: cte_wp_at_ctes_of)
   apply (drule invs_mdb')
   apply (clarsimp simp: valid_mdb'_def valid_mdb_ctes_def)
   apply (rule conjI, clarsimp)
    apply (erule (2) valid_dlistEp)
    apply simp
   apply clarsimp
   apply (erule (2) valid_dlistEn)
   apply simp
  apply (clarsimp simp: in_monad bind_assoc exec_gets)
  apply (subgoal_tac "mdb_empty_abs a")
   prefer 2
   apply (rule mdb_empty_abs.intro)
   apply (rule vmdb_abs.intro)
   apply fastforce
  apply (frule mdb_empty_abs'.intro)
  apply (simp add: mdb_empty_abs'.empty_slot_ext_det_def2 update_cdt_list_def set_cdt_list_def exec_gets set_cdt_def bind_assoc exec_get exec_put set_original_def modify_def del: fun_upd_apply | subst bind_def, simp, simp add: mdb_empty_abs'.empty_slot_ext_det_def2)+
  apply (simp add: put_def)
  apply (simp add: exec_gets exec_get exec_put del: fun_upd_apply | subst bind_def)+
 
  apply (clarsimp simp: state_relation_def)
  apply (drule updateMDB_the_lot, fastforce simp: pspace_relations_def, fastforce, fastforce)
   apply (clarsimp simp: invs'_def valid_state'_def valid_pspace'_def 
                         valid_mdb'_def valid_mdb_ctes_def)
  apply (elim conjE)
  apply (drule (4) updateMDB_the_lot, elim conjE)
  apply clarsimp
  apply (drule_tac s'=s''a and c=cap.NullCap in set_cap_not_quite_corres)
                     apply simp
                    apply simp
                   apply simp
                  apply fastforce
                 apply fastforce
                apply fastforce
               apply fastforce
              apply fastforce
             apply fastforce
            apply fastforce
           apply fastforce
          apply fastforce
         apply (erule cte_wp_at_weakenE, rule TrueI)
        apply assumption
       apply simp
      apply simp
     apply simp
    apply simp
   apply (rule refl)
  apply clarsimp
  apply (drule updateCap_stuff, elim conjE, erule (1) impE)
  apply clarsimp
  apply (drule updateMDB_the_lot, force simp: pspace_relations_def, assumption+, simp)
  apply (rule bexI)
   prefer 2
   apply (simp only: trans_state_update[symmetric])
   apply (rule set_cap_trans_state)
   apply (rule set_cap_revokable_update)
   apply (erule set_cap_cdt_update)
  apply clarsimp
  apply (thin_tac "ctes_of t = s" for t s)+
  apply (thin_tac "ksMachineState t = p" for t p)+
  apply (thin_tac "ksCurThread t = p" for t p)+
  apply (thin_tac "ksReadyQueues t = p" for t p)+
  apply (thin_tac "ksSchedulerAction t = p" for t p)+
  apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (case_tac rv')
  apply (rename_tac s_cap s_node)
  apply (subgoal_tac "cte_at slot a")
   prefer 2
   apply (fastforce elim: cte_wp_at_weakenE)
  apply (subgoal_tac "mdb_empty (ctes_of b) (cte_map slot) s_cap s_node")
   prefer 2
   apply (rule mdb_empty.intro)
   apply (rule mdb_ptr.intro)
    apply (rule vmdb.intro)
    apply (simp add: invs'_def valid_state'_def valid_pspace'_def valid_mdb'_def)
   apply (rule mdb_ptr_axioms.intro)
   apply simp
  
   apply (clarsimp simp: ghost_relation_typ_at set_cap_a_type_inv)
  apply (simp add: pspace_relations_def)
  apply (rule conjI)
   prefer 2
   apply (rule conjI)
    apply (clarsimp simp: cdt_list_relation_def)
    apply(frule invs_valid_pspace, frule invs_mdb)
    apply(subgoal_tac "no_mloop (cdt a) \<and> finite_depth (cdt a)")
     prefer 2
     apply(simp add: finite_depth valid_mdb_def)
    apply(subgoal_tac "valid_mdb_ctes (ctes_of b)")
     prefer 2
     apply(simp add: mdb_empty_def mdb_ptr_def vmdb_def)
    apply(clarsimp simp: valid_pspace_def)

    apply(case_tac "cdt a slot")
     apply(simp add: next_slot_eq[OF mdb_empty_abs'.next_slot_no_parent])
     apply(case_tac "next_slot (aa, bb) (cdt_list a) (cdt a)")
      apply(simp)
     apply(clarsimp)
     apply(frule(1) mdb_empty.n_next)
     apply(clarsimp)
     apply(erule_tac x=aa in allE, erule_tac x=bb in allE)
     apply(simp split: split_if_asm)
      apply(drule cte_map_inj_eq)
           apply(drule cte_at_next_slot)
             apply(assumption)+
      apply(simp)
     apply(subgoal_tac "(ab, bc) = slot")
      prefer 2
      apply(drule_tac cte="CTE s_cap s_node" in valid_mdbD2')
        apply(clarsimp simp: valid_mdb_ctes_def no_0_def)
       apply(frule invs_mdb', simp)
      apply(clarsimp)
      apply(rule cte_map_inj_eq)
           apply(assumption)
          apply(drule(3) cte_at_next_slot', assumption)
         apply(assumption)+
     apply(simp)
     apply(drule_tac p="(aa, bb)" in no_parent_not_next_slot)
        apply(assumption)+
     apply(clarsimp)

    apply(simp add: next_slot_eq[OF mdb_empty_abs'.next_slot] split del: split_if)
    apply(case_tac "next_slot (aa, bb) (cdt_list a) (cdt a)")
     apply(simp)
    apply(case_tac "(aa, bb) = slot", simp)
    apply(case_tac "next_slot (aa, bb) (cdt_list a) (cdt a) = Some slot")
     apply(simp)
     apply(case_tac "next_slot ac (cdt_list a) (cdt a)", simp)
     apply(simp)
     apply(frule(1) mdb_empty.n_next)
     apply(clarsimp)
     apply(erule_tac x=aa in allE', erule_tac x=bb in allE)
     apply(erule_tac x=ac in allE, erule_tac x=bd in allE)
     apply(clarsimp split: split_if_asm)
      apply(drule(1) no_self_loop_next)
      apply(simp)
     apply(drule_tac cte="CTE cap' node'" in valid_mdbD1')
       apply(fastforce simp: valid_mdb_ctes_def no_0_def)
      apply(simp add: valid_mdb'_def)
     apply(clarsimp)
    apply(simp)
    apply(frule(1) mdb_empty.n_next)
    apply(erule_tac x=aa in allE, erule_tac x=bb in allE)
    apply(clarsimp split: split_if_asm)
     apply(drule(1) no_self_loop_prev)
     apply(clarsimp)
     apply(drule_tac cte="CTE s_cap s_node" in valid_mdbD2')
       apply(clarsimp simp: valid_mdb_ctes_def no_0_def)
      apply(erule invs_mdb')
     apply(clarsimp)
     apply(drule cte_map_inj_eq)
          apply(drule(3) cte_at_next_slot')
          apply(assumption)+
     apply(simp)
    apply(erule disjE)
     apply(drule cte_map_inj_eq)
          apply(drule(3) cte_at_next_slot)
          apply(assumption)+
     apply(simp)
    apply(simp)
   apply (simp add: revokable_relation_def)
   apply (clarsimp simp: in_set_cap_cte_at)   
   apply (rule conjI)
    apply clarsimp
    apply (drule(1) mdb_empty.n_revokable)
    apply clarsimp
   apply clarsimp
   apply (drule (1) mdb_empty.n_revokable)
   apply (subgoal_tac "null_filter (caps_of_state a) (aa,bb) \<noteq> None")
    prefer 2
    apply (drule set_cap_caps_of_state_monad)
    apply (force simp: null_filter_def)
   apply clarsimp
   apply (subgoal_tac "cte_at (aa, bb) a")
    prefer 2
    apply (drule null_filter_caps_of_stateD, erule cte_wp_cte_at)
   apply (drule (2) cte_map_inj_ps, fastforce)
   apply simp
  apply (clarsimp simp add: cdt_relation_def)
  apply (subst mdb_empty_abs.descendants, assumption)
  apply (subst mdb_empty.descendants, assumption)
  apply clarsimp
  apply (frule_tac p="(aa, bb)" in in_set_cap_cte_at)
  apply clarsimp
  apply (frule (2) cte_map_inj_ps, fastforce)
  apply simp
  apply (case_tac "slot \<in> descendants_of (aa,bb) (cdt a)")
   apply (subst inj_on_image_set_diff)
      apply (rule inj_on_descendants_cte_map)
         apply fastforce
        apply fastforce
       apply fastforce
      apply fastforce
     apply fastforce
    apply simp
   apply simp
  apply simp
  apply (subgoal_tac "cte_map slot \<notin> descendants_of' (cte_map (aa,bb)) (ctes_of b)")  
   apply simp
  apply (erule_tac x=aa in allE, erule allE, erule (1) impE)
  apply (drule_tac s="cte_map ` u" for u in sym)
  apply clarsimp
  apply (drule cte_map_inj_eq, assumption)
      apply (erule descendants_of_cte_at, fastforce)
     apply fastforce
    apply fastforce
   apply fastforce
  apply simp
  done



text {* Some facts about is_final_cap/isFinalCapability *}

lemma isFinalCapability_inv:
  "\<lbrace>P\<rbrace> isFinalCapability cap \<lbrace>\<lambda>_. P\<rbrace>"
  apply (simp add: isFinalCapability_def Let_def
              split del: split_if cong: if_cong)
  apply (rule hoare_pre, wp)
   apply (rule hoare_post_imp [where Q="\<lambda>s. P"], simp)
   apply wp
  apply simp
  done

definition
  final_matters' :: "capability \<Rightarrow> bool"
where
 "final_matters' cap \<equiv> case cap of
    EndpointCap ref bdg s r g \<Rightarrow> True
  | AsyncEndpointCap ref bdg s r \<Rightarrow> True
  | ThreadCap ref \<Rightarrow> True
  | CNodeCap ref bits gd gs \<Rightarrow> True
  | Zombie ptr zb n \<Rightarrow> True
  | IRQHandlerCap irq \<Rightarrow> True
  | ArchObjectCap acap \<Rightarrow> (case acap of
    PageCap ref rghts sz mapdata \<Rightarrow> False
  | ASIDControlCap \<Rightarrow> False
  | _ \<Rightarrow> True)
  | _ \<Rightarrow> False"

lemma final_matters_Master:
  "final_matters' (capMasterCap cap) = final_matters' cap"
  by (simp add: capMasterCap_def split: capability.split arch_capability.split,
      simp add: final_matters'_def)

lemma final_matters_sameRegion_sameObject:
  "final_matters' cap \<Longrightarrow> sameRegionAs cap cap' = sameObjectAs cap cap'"
  apply (rule iffI)
   apply (erule sameRegionAsE)
      apply (simp add: sameObjectAs_def3)
      apply (clarsimp simp: isCap_simps sameObjectAs_sameRegionAs final_matters'_def
        split:capability.splits arch_capability.splits)+
  done

lemma final_matters_sameRegion_sameObject2:
  "\<lbrakk> final_matters' cap'; \<not> isUntypedCap cap; \<not> isIRQHandlerCap cap' \<rbrakk>
     \<Longrightarrow> sameRegionAs cap cap' = sameObjectAs cap cap'"
  apply (rule iffI)
   apply (erule sameRegionAsE)
      apply (simp add: sameObjectAs_def3)
      apply (fastforce simp: isCap_simps final_matters'_def)
     apply simp
    apply (clarsimp simp: final_matters'_def isCap_simps)
   apply (clarsimp simp: final_matters'_def isCap_simps)
  apply (erule sameObjectAs_sameRegionAs)
  done

lemma notFinal_prev_or_next:
  "\<lbrakk> \<not> isFinal cap x (cteCaps_of s); mdb_chunked (ctes_of s);
      valid_dlist (ctes_of s); no_0 (ctes_of s);
      ctes_of s x = Some (CTE cap node); final_matters' cap \<rbrakk>
     \<Longrightarrow> (\<exists>cap' node'. ctes_of s (mdbPrev node) = Some (CTE cap' node')
              \<and> sameObjectAs cap cap')
      \<or> (\<exists>cap' node'. ctes_of s (mdbNext node) = Some (CTE cap' node')
              \<and> sameObjectAs cap cap')"
  apply (erule not_FinalE)
   apply (clarsimp simp: isCap_simps final_matters'_def)
  apply (clarsimp simp: mdb_chunked_def cte_wp_at_ctes_of cteCaps_of_def
                   del: disjCI)
  apply (erule_tac x=x in allE, erule_tac x=p in allE)
  apply simp
  apply (case_tac z, simp add: sameObjectAs_sameRegionAs)
  apply (elim conjE disjE, simp_all add: is_chunk_def)
   apply (rule disjI2)
   apply (drule tranclD)
   apply (clarsimp simp: mdb_next_unfold)
   apply (drule spec[where x="mdbNext node"])
   apply simp
   apply (drule mp[where P="ctes_of s \<turnstile> x \<leadsto>\<^sup>+ mdbNext node"])
    apply (rule trancl.intros(1), simp add: mdb_next_unfold)
   apply clarsimp
   apply (drule rtranclD)
   apply (erule disjE, clarsimp+)
   apply (drule tranclD)
   apply (clarsimp simp: mdb_next_unfold final_matters_sameRegion_sameObject)
  apply (rule disjI1)
  apply clarsimp
  apply (drule tranclD2)
  apply clarsimp
  apply (frule vdlist_nextD0)
    apply clarsimp
   apply assumption
  apply (clarsimp simp: mdb_prev_def)
  apply (drule rtranclD)
  apply (erule disjE, clarsimp+)
  apply (drule spec, drule(1) mp)
  apply (drule mp, rule trancl_into_rtrancl, erule trancl.intros(1))
  apply clarsimp
  apply (drule iffD1 [OF final_matters_sameRegion_sameObject, rotated])
   apply (subst final_matters_Master[symmetric])
   apply (subst(asm) final_matters_Master[symmetric])
   apply (clarsimp simp: sameObjectAs_def3)
  apply (clarsimp simp: sameObjectAs_def3)
  done

lemma isFinal:
  "\<lbrace>\<lambda>s. valid_mdb' s \<and> cte_wp_at' (op = cte) x s
          \<and> final_matters' (cteCap cte)
          \<and> Q (isFinal (cteCap cte) x (cteCaps_of s)) s\<rbrace>
    isFinalCapability cte
   \<lbrace>Q\<rbrace>"
  unfolding isFinalCapability_def 
  apply (cases cte)
  apply (rename_tac cap node)
  apply (unfold Let_def)
  apply (simp only: if_False)
  apply (wp getCTE_wp')
  apply (cases "mdbPrev (cteMDBNode cte) = nullPointer")
   apply simp
   apply wp
   apply (clarsimp simp: valid_mdb_ctes_def valid_mdb'_def
                         cte_wp_at_ctes_of)
   apply (rule conjI, clarsimp simp: nullPointer_def)
    apply (erule rsubst[where P="\<lambda>x. Q x s" for s], simp)
    apply (rule classical)
    apply (drule(5) notFinal_prev_or_next)
    apply clarsimp
   apply (clarsimp simp: nullPointer_def)
   apply (erule rsubst[where P="\<lambda>x. Q x s" for s])
   apply (rule sym, rule iffI)
    apply (rule classical)
    apply (drule(5) notFinal_prev_or_next)
    apply clarsimp
   apply clarsimp
   apply (clarsimp simp: cte_wp_at_ctes_of cteCaps_of_def)
   apply (case_tac cte)
   apply clarsimp
   apply (clarsimp simp add: isFinal_def)
   apply (erule_tac x="mdbNext node" in allE)
   apply simp
   apply (erule impE)
    apply (clarsimp simp: valid_mdb'_def valid_mdb_ctes_def)
    apply (drule (1) mdb_chain_0_no_loops)
    apply simp
   apply (clarsimp simp: sameObjectAs_def3 isCap_simps)
  apply simp
  apply (wp getCTE_wp')
  apply (clarsimp simp: cte_wp_at_ctes_of
                        valid_mdb_ctes_def valid_mdb'_def)
  apply (case_tac cte)
  apply clarsimp
  apply (rule conjI)
   apply clarsimp
   apply (erule rsubst[where P="\<lambda>x. Q x s" for s])
   apply clarsimp
   apply (clarsimp simp: isFinal_def cteCaps_of_def)
   apply (erule_tac x="mdbPrev node" in allE)
   apply simp
   apply (erule impE)
    apply clarsimp
    apply (drule (1) mdb_chain_0_no_loops)
    apply (subgoal_tac "ctes_of s (mdbNext node) = Some (CTE cap node)")
     apply clarsimp
    apply (erule (1) valid_dlistEp)
     apply clarsimp
    apply (case_tac cte')
    apply clarsimp
   apply (clarsimp simp add: sameObjectAs_def3 isCap_simps)
  apply clarsimp
  apply (rule conjI)
   apply clarsimp
   apply (erule rsubst[where P="\<lambda>x. Q x s" for s], simp)
   apply (rule classical, drule(5) notFinal_prev_or_next)
   apply (clarsimp simp: sameObjectAs_sym nullPointer_def)
  apply (clarsimp simp: nullPointer_def)
  apply (erule rsubst[where P="\<lambda>x. Q x s" for s])
  apply (rule sym, rule iffI)
   apply (rule classical, drule(5) notFinal_prev_or_next)
   apply (clarsimp simp: sameObjectAs_sym)
   apply auto[1]
  apply (clarsimp simp: isFinal_def cteCaps_of_def)
  apply (case_tac cte)
  apply (erule_tac x="mdbNext node" in allE)
  apply simp
  apply (erule impE)
   apply clarsimp
   apply (drule (1) mdb_chain_0_no_loops)
   apply simp
  apply clarsimp
  apply (clarsimp simp: isCap_simps sameObjectAs_def3)
  done

lemma (in vmdb) isFinal_no_subtree: 
  "\<lbrakk> m \<turnstile> sl \<rightarrow> p; isFinal cap sl (option_map cteCap o m);
      m sl = Some (CTE cap n); final_matters' cap \<rbrakk> \<Longrightarrow> False"
  apply (erule subtree.induct)
   apply (case_tac "c'=sl", simp)
   apply (clarsimp simp: isFinal_def parentOf_def mdb_next_unfold cteCaps_of_def)
   apply (erule_tac x="mdbNext n" in allE)
   apply simp
   apply (clarsimp simp: isMDBParentOf_CTE final_matters_sameRegion_sameObject)
   apply (clarsimp simp: isCap_simps sameObjectAs_def3)
  apply clarsimp
  done

lemma isFinal_no_descendants: 
  "\<lbrakk> isFinal cap sl (cteCaps_of s); ctes_of s sl = Some (CTE cap n);
      valid_mdb' s; final_matters' cap \<rbrakk> 
  \<Longrightarrow> descendants_of' sl (ctes_of s) = {}"
  apply (clarsimp simp add: descendants_of'_def cteCaps_of_def)
  apply (erule(3) vmdb.isFinal_no_subtree[rotated])
  apply unfold_locales[1]
  apply (simp add: valid_mdb'_def)
  done

lemma (in vmdb) isFinal_untypedParent:
  assumes x: "m slot = Some cte" "isFinal (cteCap cte) slot (option_map cteCap o m)" 
             "final_matters' (cteCap cte) \<and> \<not> isIRQHandlerCap (cteCap cte)"
  shows
  "m \<turnstile> x \<rightarrow> slot \<Longrightarrow>  
  (\<exists>cte'. m x = Some cte' \<and> isUntypedCap (cteCap cte') \<and> RetypeDecls_H.sameRegionAs (cteCap cte') (cteCap cte))"
  apply (cases "x=slot", simp)
  apply (insert x)
  apply (frule subtree_mdb_next)
  apply (drule subtree_parent)
  apply (drule tranclD)
  apply clarsimp
  apply (clarsimp simp: mdb_next_unfold parentOf_def isFinal_def)
  apply (case_tac cte')
  apply (rename_tac c' n')
  apply (cases cte)
  apply (rename_tac c n)
  apply simp
  apply (erule_tac x=x in allE)
  apply clarsimp
  apply (drule isMDBParent_sameRegion)
  apply simp
  apply (rule classical, simp)
  apply (simp add: final_matters_sameRegion_sameObject2
                   sameObjectAs_sym)
  done

lemma isFinal2:
  "\<lbrace>\<lambda>s. cte_wp_at' (op = cte) sl s \<and> valid_mdb' s\<rbrace>
     isFinalCapability cte
   \<lbrace>\<lambda>rv s. rv \<and> final_matters' (cteCap cte) \<longrightarrow>
             isFinal (cteCap cte) sl (cteCaps_of s)\<rbrace>"
  apply (cases "final_matters' (cteCap cte)")
   apply simp
   apply (wp isFinal[where x=sl])
   apply simp
  apply (simp|wp)+
  done

lemma no_fail_isFinalCapability [wp]:
  "no_fail (valid_mdb' and cte_wp_at' (op = cte) p) (isFinalCapability cte)"
  apply (simp add: isFinalCapability_def)
  apply (clarsimp simp: Let_def split del: split_if)
  apply (rule no_fail_pre, wp getCTE_wp')
  apply (clarsimp simp: valid_mdb'_def valid_mdb_ctes_def cte_wp_at_ctes_of nullPointer_def)
  apply (rule conjI)
   apply clarsimp
   apply (erule (2) valid_dlistEp)
   apply simp
  apply clarsimp
  apply (rule conjI)
   apply (erule (2) valid_dlistEn)
   apply simp
  apply clarsimp
  apply (rule valid_dlistEn, assumption+)
  apply (erule (2) valid_dlistEp)
  apply simp
  done

lemma corres_gets_lift:
  assumes inv: "\<And>P. \<lbrace>P\<rbrace> g \<lbrace>\<lambda>_. P\<rbrace>"
  assumes res: "\<lbrace>Q'\<rbrace> g \<lbrace>\<lambda>r s. r = g' s\<rbrace>"
  assumes Q: "\<And>s. Q s \<Longrightarrow> Q' s"
  assumes nf: "no_fail Q g"
  shows "corres r P Q f (gets g') \<Longrightarrow> corres r P Q f g"
  apply (clarsimp simp add: corres_underlying_def simpler_gets_def)
  apply (drule (1) bspec)
  apply (rule conjI)
   apply clarsimp
   apply (rule bexI)
    prefer 2
    apply assumption
   apply simp 
   apply (frule in_inv_by_hoareD [OF inv])
   apply simp
   apply (drule use_valid, rule res)
    apply (erule Q)
   apply simp
  apply (insert nf)
  apply (clarsimp simp: no_fail_def)
  done
  
lemma obj_refs_Master:
  "\<lbrakk> cap_relation cap cap'; P cap \<rbrakk>
      \<Longrightarrow> obj_refs cap =
           (if capClass (capMasterCap cap') = PhysicalClass
                  \<and> \<not> isUntypedCap (capMasterCap cap')
            then {capUntypedPtr (capMasterCap cap')} else {})"
  by (clarsimp simp: isCap_simps
              split: cap_relation_split_asm arch_cap.split_asm)

lemma final_cap_corres':
  "final_matters' (cteCap cte) \<Longrightarrow>
   corres op = (invs and cte_wp_at (op = cap) ptr)
               (invs' and cte_wp_at' (op = cte) (cte_map ptr))
       (is_final_cap cap) (isFinalCapability cte)"
  apply (rule corres_gets_lift)
      apply (rule isFinalCapability_inv)
     apply (rule isFinal[where x="cte_map ptr"])
    apply clarsimp
    apply (rule conjI, clarsimp)
    apply (rule refl)
   apply (rule no_fail_pre, wp, fastforce)
  apply (simp add: is_final_cap_def)
  apply (clarsimp simp: cte_wp_at_ctes_of cteCaps_of_def state_relation_def)
  apply (frule (1) pspace_relation_ctes_ofI)
    apply fastforce
   apply fastforce
  apply clarsimp
  apply (rule iffI)
   apply (simp add: is_final_cap'_def2 isFinal_def)
   apply clarsimp
   apply (subgoal_tac "obj_refs cap \<noteq> {} \<or> cap_irqs cap \<noteq> {}")
    prefer 2
    apply (erule_tac x=a in allE)
    apply (erule_tac x=b in allE)
    apply (clarsimp simp: cte_wp_at_def obj_irq_refs_Int)
   apply (subgoal_tac "ptr = (a,b)")
    prefer 2
    apply (erule_tac x="fst ptr" in allE)
    apply (erule_tac x="snd ptr" in allE)
    apply (clarsimp simp: cte_wp_at_def obj_irq_refs_Int)
   apply clarsimp
   apply (rule context_conjI)
    apply (clarsimp simp: isCap_simps)
    apply (cases cap, auto)[1]
   apply clarsimp
   apply (drule_tac x=p' in pspace_relation_cte_wp_atI, assumption)
    apply fastforce
   apply clarsimp
   apply (erule_tac x=aa in allE)
   apply (erule_tac x=ba in allE)
   apply (clarsimp simp: cte_wp_at_caps_of_state)
   apply (clarsimp simp: sameObjectAs_def3 obj_refs_Master cap_irqs_relation_Master
                         obj_irq_refs_Int cong: if_cong)
  apply (clarsimp simp: isFinal_def is_final_cap'_def3)
  apply (rule_tac x="fst ptr" in exI)
  apply (rule_tac x="snd ptr" in exI)
  apply (rule conjI)
   apply (clarsimp simp: cte_wp_at_def final_matters'_def
                         obj_irq_refs_Int
                  split: cap_relation_split_asm arch_cap.split_asm)
  apply clarsimp
  apply (drule_tac p="(a,b)" in cte_wp_at_eqD)
  apply clarsimp
  apply (frule_tac slot="(a,b)" in pspace_relation_ctes_ofI, assumption)
    apply fastforce
   apply fastforce
  apply clarsimp
  apply (frule_tac p="(a,b)" in cte_wp_valid_cap, fastforce)
  apply (erule_tac x="cte_map (a,b)" in allE)
  apply simp
  apply (erule impCE, simp, drule cte_map_inj_eq)
        apply (erule cte_wp_at_weakenE, rule TrueI)
       apply (erule cte_wp_at_weakenE, rule TrueI)
      apply fastforce
     apply fastforce
    apply (erule invs_distinct)
   apply simp
  apply (frule_tac p=ptr in cte_wp_valid_cap, fastforce)
  apply (clarsimp simp: cte_wp_at_def obj_irq_refs_Int)
  apply (rule conjI)
   apply (rule classical)
   apply (frule(1) zombies_finalD2[OF _ _ _ invs_zombies],
          simp?, clarsimp, assumption+)
   apply (clarsimp simp: sameObjectAs_def3 isCap_simps valid_cap_def
                         obj_at_def is_obj_defs a_type_def final_matters'_def
                  split: cap.split_asm arch_cap.split_asm
                         option.split_asm split_if_asm,
          simp_all add: is_cap_defs)
  apply (rule classical)
  apply (clarsimp simp: cap_irqs_def cap_irq_opt_def sameObjectAs_def3 isCap_simps
                 split: cap.split_asm)
  done

lemma final_cap_corres:
  "corres (\<lambda>rv rv'. final_matters' (cteCap cte) \<longrightarrow> rv = rv')
          (invs and cte_wp_at (op = cap) ptr)
          (invs' and cte_wp_at' (op = cte) (cte_map ptr))
       (is_final_cap cap) (isFinalCapability cte)"
  apply (cases "final_matters' (cteCap cte)")
   apply simp
   apply (erule final_cap_corres')
  apply (subst bind_return[symmetric],
         rule corres_symb_exec_r)
     apply (rule corres_no_failI)
      apply wp
     apply (clarsimp simp: in_monad is_final_cap_def simpler_gets_def)
    apply (wp isFinalCapability_inv)
  apply (rule no_fail_pre, rule no_fail_isFinalCapability[where p="cte_map ptr"])
  apply fastforce
  done

text {* Facts about finalise_cap/finaliseCap and
        cap_delete_one/cteDelete in no particular order *}


definition
  finaliseCapTrue_standin_simple_def:
  "finaliseCapTrue_standin cap fin \<equiv> finaliseCap cap fin True"

context
begin

declare if_cong [cong]

lemmas finaliseCapTrue_standin_def
    = finaliseCapTrue_standin_simple_def
        [unfolded finaliseCap_def, simplified]

lemmas cteDeleteOne_def'
    = eq_reflection [OF cteDeleteOne_def]
lemmas cteDeleteOne_def
    = cteDeleteOne_def'[folded finaliseCapTrue_standin_simple_def]

crunch typ_at'[wp]: cteDeleteOne, suspend "\<lambda>s. P (typ_at' T p s)"
  (wp: crunch_wps simp: crunch_simps unless_def)

end

lemmas epCancelAll_typs[wp] = typ_at_lifts [OF epCancelAll_typ_at']
lemmas aepCancelAll_typs[wp] = typ_at_lifts [OF aepCancelAll_typ_at']
lemmas suspend_typs[wp] = typ_at_lifts [OF suspend_typ_at']

lemma finaliseCap_cases[wp]:
  "\<lbrace>\<top>\<rbrace>
     finaliseCap cap final flag
   \<lbrace>\<lambda>rv s. fst rv = NullCap \<and> (\<forall>irq. snd rv = Some irq \<longrightarrow> final \<and> cap = IRQHandlerCap irq)
     \<or>
       isZombie (fst rv) \<and> final \<and> \<not> flag \<and> snd rv = None
        \<and> capUntypedPtr (fst rv) = capUntypedPtr cap
        \<and> (isThreadCap cap \<or> isCNodeCap cap \<or> isZombie cap)\<rbrace>"
  apply (simp add: finaliseCap_def ArchRetype_H.finaliseCap_def Let_def
                   getThreadCSpaceRoot
             cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply ((wp | simp add: isCap_simps split del: split_if
              | wpc
              | simp only: valid_NullCap fst_conv snd_conv)+)[1]
  apply (simp only: simp_thms fst_conv snd_conv option.simps if_cancel
                    o_def)
  apply (intro allI impI conjI TrueI)
  apply (auto simp add: isCap_simps)
  done

crunch aligned'[wp]: finaliseCap "pspace_aligned'"
  (simp: crunch_simps assertE_def unless_def
 ignore: getObject setObject forM ignoreFailure
     wp: getObject_inv loadObject_default_inv crunch_wps)

crunch distinct'[wp]: finaliseCap "pspace_distinct'"
  (ignore: getObject setObject forM ignoreFailure
     simp: crunch_simps assertE_def unless_def
       wp: getObject_inv loadObject_default_inv crunch_wps)

crunch typ_at'[wp]: finaliseCap "\<lambda>s. P (typ_at' T p s)"
  (simp: crunch_simps assertE_def ignore: getObject setObject
     wp: getObject_inv loadObject_default_inv crunch_wps)

crunch it'[wp]: finaliseCap "\<lambda>s. P (ksIdleThread s)"
  (ignore: getObject setObject forM ignoreFailure maskInterrupt
   wp: mapM_x_wp_inv mapM_wp' hoare_drop_imps 
   simp: whenE_def crunch_simps unless_def)

crunch vs_lookup[wp]: flush_space "\<lambda>s. P (vs_lookup s)"
  (wp: crunch_wps)


(* Ugh, required to be able to split out the abstract invs *)
lemma finaliseCap_True_invs[wp]:
  "\<lbrace>invs'\<rbrace> finaliseCap cap final True \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: finaliseCap_def Let_def)
  apply safe 
    apply (wp irqs_masked_lift| simp)+
  done

crunch invs'[wp]: flushSpace "invs'" (ignore: doMachineOp)

lemma ct_not_inQ_ksArchState_update[simp]:
  "ct_not_inQ (s\<lparr>ksArchState := v\<rparr>) = ct_not_inQ s"
  by (simp add: ct_not_inQ_def)

lemma invs_asid_update_strg':
  "invs' s \<and> tab = armKSASIDTable (ksArchState s) \<longrightarrow>
   invs' (s\<lparr>ksArchState := armKSASIDTable_update 
            (\<lambda>_. tab (asid := None)) (ksArchState s)\<rparr>)"
  apply (simp add: invs'_def)
  apply (simp add: valid_state'_def)
  apply (simp add: valid_global_refs'_def global_refs'_def valid_arch_state'_def valid_asid_table'_def valid_machine_state'_def ct_idle_or_in_cur_domain'_def tcb_in_cur_domain'_def)
  apply (auto simp add: ran_def split: split_if_asm)
  done

lemma invalidateASIDEntry_invs' [wp]:
  "\<lbrace>invs'\<rbrace> invalidateASIDEntry asid \<lbrace>\<lambda>r. invs'\<rbrace>"
  apply (simp add: invalidateASIDEntry_def invalidateASID_def 
                   invalidateHWASIDEntry_def bind_assoc)
  apply (wp loadHWASID_wp | simp)+
  apply (clarsimp simp: fun_upd_def[symmetric])
  apply (rule conjI)
   apply (clarsimp simp: invs'_def valid_state'_def)
   apply (rule conjI)
    apply (simp add: valid_global_refs'_def
                     global_refs'_def)
   apply (simp add: valid_arch_state'_def ran_def
                    valid_asid_table'_def is_inv_None_upd
                    valid_machine_state'_def
                    comp_upd_simp fun_upd_def[symmetric]
                    inj_on_fun_upd_elsewhere
                    valid_asid_map'_def
                    ct_idle_or_in_cur_domain'_def tcb_in_cur_domain'_def)
   apply (auto elim!: subset_inj_on)[1]
  apply (clarsimp simp: invs'_def valid_state'_def)
  apply (rule conjI)
   apply (simp add: valid_global_refs'_def
                    global_refs'_def)
  apply (rule conjI)
   apply (simp add: valid_arch_state'_def ran_def
                    valid_asid_table'_def None_upd_eq
                    fun_upd_def[symmetric] comp_upd_simp)
  apply (simp add: valid_machine_state'_def ct_idle_or_in_cur_domain'_def tcb_in_cur_domain'_def)
  done

lemma deleteASIDPool_invs[wp]:
  "\<lbrace>invs'\<rbrace> deleteASIDPool asid pool \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: deleteASIDPool_def)
  apply wp
    apply (simp del: fun_upd_apply)
    apply (strengthen invs_asid_update_strg')
  apply (wp mapM_wp' getObject_inv loadObject_default_inv
              | simp)+
  done

lemma invalidateASIDEntry_valid_ap' [wp]:
  "\<lbrace>valid_asid_pool' p\<rbrace> invalidateASIDEntry asid \<lbrace>\<lambda>r. valid_asid_pool' p\<rbrace>"
  apply (simp add: invalidateASIDEntry_def invalidateASID_def 
                   invalidateHWASIDEntry_def bind_assoc)
  apply (wp loadHWASID_wp | simp)+
  apply (case_tac p)
  apply (clarsimp simp del: fun_upd_apply)
  done

lemmas flushSpace_typ_ats' [wp] = typ_at_lifts [OF flushSpace_typ_at']

lemma deleteASID_invs'[wp]:
  "\<lbrace>invs'\<rbrace> deleteASID asid pd \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: deleteASID_def cong: option.case_cong)
  apply (rule hoare_pre)
   apply (wp | wpc)+
      apply (rule_tac Q="\<lambda>rv. valid_obj' (injectKO rv) and invs'"
                in hoare_post_imp)
     apply (clarsimp split: split_if_asm del: subsetI)
     apply (simp add: fun_upd_def[symmetric] valid_obj'_def)
     apply (case_tac r, simp)
     apply (subst inv_f_f, rule inj_onI, simp)+
     apply (rule conjI)
      apply clarsimp
      apply (drule subsetD, blast)
      apply clarsimp
     apply (auto dest!: ran_del_subset)[1]
    apply (wp getObject_valid_obj getObject_inv loadObject_default_inv
             | simp add: objBits_simps archObjSize_def pageBits_def)+
  apply clarsimp
  done

lemma arch_finaliseCap_invs[wp]:
  "\<lbrace>invs' and valid_cap' (ArchObjectCap cap)\<rbrace>
     ArchRetypeDecls_H.finaliseCap cap fin
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: ArchRetype_H.finaliseCap_def)
  apply (rule hoare_pre)
   apply (wp | wpc)+
  apply clarsimp
  done

lemma arch_finaliseCap_removeable[wp]:
  "\<lbrace>\<lambda>s. s \<turnstile>' ArchObjectCap cap \<and> invs' s
       \<and> (final \<and> final_matters' (ArchObjectCap cap)
            \<longrightarrow> isFinal (ArchObjectCap cap) slot (cteCaps_of s))\<rbrace>
     ArchRetypeDecls_H.finaliseCap cap final
   \<lbrace>\<lambda>rv s. isNullCap rv \<and> removeable' slot s (ArchObjectCap cap)\<rbrace>"
  apply (simp add: ArchRetype_H.finaliseCap_def
                   removeable'_def)
  apply (rule hoare_pre)
   apply (wp | wpc)+
  apply simp
  done

lemma isZombie_Null:
  "\<not> isZombie NullCap"
  by (simp add: isCap_simps)

lemma prepares_delete_helper'':
  assumes x: "\<lbrace>P\<rbrace> f \<lbrace>\<lambda>rv. ko_wp_at' (Not \<circ> live') p\<rbrace>"
  shows      "\<lbrace>P and K ((\<forall>x. cte_refs' cap x = {})
                          \<and> zobj_refs' cap = {p}
                          \<and> threadCapRefs cap = {})\<rbrace>
                 f \<lbrace>\<lambda>rv s. removeable' sl s cap\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (rule hoare_strengthen_post [OF x])
  apply (clarsimp simp: removeable'_def)
  done

lemma ctes_of_cteCaps_of_lift:
  "\<lbrakk> \<And>P. \<lbrace>\<lambda>s. P (ctes_of s)\<rbrace> f \<lbrace>\<lambda>rv s. P (ctes_of s)\<rbrace> \<rbrakk>
     \<Longrightarrow> \<lbrace>\<lambda>s. P (cteCaps_of s)\<rbrace> f \<lbrace>\<lambda>rv s. P (cteCaps_of s)\<rbrace>"
  by (simp add: cteCaps_of_def)

crunch ctes_of[wp]: finaliseCapTrue_standin "\<lambda>s. P (ctes_of s)"
  (wp: crunch_wps simp: crunch_simps)

lemma cteDeleteOne_cteCaps_of:
  "\<lbrace>\<lambda>s. (cte_wp_at' (\<lambda>cte. \<exists>final. finaliseCap (cteCap cte) final True \<noteq> fail) p s \<longrightarrow>
          P (cteCaps_of s(p \<mapsto> NullCap)))\<rbrace>
     cteDeleteOne p
   \<lbrace>\<lambda>rv s. P (cteCaps_of s)\<rbrace>"
  apply (simp add: cteDeleteOne_def unless_def split_def)
  apply (rule hoare_seq_ext [OF _ getCTE_sp])
  apply (case_tac "\<forall>final. finaliseCap (cteCap cte) final True = fail")
   apply (simp add: finaliseCapTrue_standin_simple_def)
   apply wp
   apply (clarsimp simp: cte_wp_at_ctes_of cteCaps_of_def
                         finaliseCap_def isCap_simps)
   apply (drule_tac x=s in fun_cong)
   apply (simp add: return_def fail_def)
  apply (wp emptySlot_cteCaps_of)
    apply (simp add: cteCaps_of_def)
    apply (wp_once hoare_drop_imps)
    apply (wp isFinalCapability_inv getCTE_wp')
  apply (clarsimp simp: cteCaps_of_def cte_wp_at_ctes_of)
  apply (auto simp: fun_upd_idem fun_upd_def[symmetric] o_def)
  done

lemma cteDeleteOne_isFinal:
  "\<lbrace>\<lambda>s. isFinal cap slot (cteCaps_of s)\<rbrace>
     cteDeleteOne p
   \<lbrace>\<lambda>rv s. isFinal cap slot (cteCaps_of s)\<rbrace>"
  apply (wp cteDeleteOne_cteCaps_of)
  apply (clarsimp simp: isFinal_def sameObjectAs_def2)
  done

lemmas setEndpoint_cteCaps_of[wp] = ctes_of_cteCaps_of_lift [OF setEndpoint_ctes_of]
lemmas setAsyncEP_cteCaps_of[wp] = ctes_of_cteCaps_of_lift [OF setAsyncEP_ctes_of]
lemmas setQueue_cteCaps_of[wp] = ctes_of_cteCaps_of_lift [OF setQueue_ctes_of]
lemmas threadSet_cteCaps_of = ctes_of_cteCaps_of_lift [OF threadSet_ctes_of]

crunch isFinal: setSchedulerAction "\<lambda>s. isFinal cap slot (cteCaps_of s)"
  (simp: cteCaps_of_def)

crunch isFinal: suspend "\<lambda>s. isFinal cap slot (cteCaps_of s)"
  (ignore: setObject getObject threadSet
       wp: threadSet_cteCaps_of crunch_wps
     simp: crunch_simps unless_def)

lemma isThreadCap_threadCapRefs_tcbptr:
  "isThreadCap cap \<Longrightarrow> threadCapRefs cap = {capTCBPtr cap}"
  by (clarsimp simp: isCap_simps)

lemma isArchObjectCap_Cap_capCap:
  "isArchObjectCap cap \<Longrightarrow> ArchObjectCap (capCap cap) = cap"
  by (clarsimp simp: isCap_simps)

lemma cteDeleteOne_deletes[wp]:
  "\<lbrace>\<top>\<rbrace> cteDeleteOne p \<lbrace>\<lambda>rv s. cte_wp_at' (\<lambda>c. cteCap c = NullCap) p s\<rbrace>"
  apply (subst tree_cte_cteCap_eq[unfolded o_def])
  apply (wp cteDeleteOne_cteCaps_of)
  apply clarsimp
  done

crunch irq_node'[wp]: finaliseCap "\<lambda>s. P (irq_node' s)"
  (wp: mapM_x_wp crunch_wps getObject_inv loadObject_default_inv
       updateObject_default_inv setObject_ksInterrupt
       ignore: getObject setObject simp: crunch_simps unless_def)

lemma deletingIRQHandler_removeable':
  "\<lbrace>invs' and (\<lambda>s. isFinal (IRQHandlerCap irq) slot (cteCaps_of s))
          and K (cap = IRQHandlerCap irq)\<rbrace>
     deletingIRQHandler irq
   \<lbrace>\<lambda>rv s. removeable' slot s cap\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (simp add: deletingIRQHandler_def getIRQSlot_def locateSlot_conv
                   getInterruptState_def)
  apply (simp add: removeable'_def tree_cte_cteCap_eq[unfolded o_def])
  apply (subst tree_cte_cteCap_eq[unfolded o_def])+
  apply (wp hoare_use_eq_irq_node' [OF cteDeleteOne_irq_node' cteDeleteOne_cteCaps_of])
  apply (clarsimp simp: cte_level_bits_def ucast_nat_def split: option.split_asm)
  done

lemma finaliseCap_cte_refs:
  "\<lbrace>\<lambda>s. s \<turnstile>' cap\<rbrace>
     finaliseCap cap final flag
   \<lbrace>\<lambda>rv s. fst rv \<noteq> NullCap \<longrightarrow> cte_refs' (fst rv) = cte_refs' cap\<rbrace>"
  apply (simp  add: finaliseCap_def Let_def getThreadCSpaceRoot
                    ArchRetype_H.finaliseCap_def
             cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply (wp | wpc | simp only: o_def)+
  apply (frule valid_capAligned)
  apply (cases cap, simp_all add: isCap_simps)
   apply (clarsimp simp: tcb_cte_cases_def word32_count_from_top)
  apply clarsimp
  apply (rule ext, simp)
  apply (rule image_cong [OF _ refl])
  apply (fastforce simp: capAligned_def objBits_simps shiftL_nat)
  done

lemma deletingIRQHandler_final:
  "\<lbrace>\<lambda>s. isFinal cap slot (cteCaps_of s)
             \<and> (\<forall>final. finaliseCap cap final True = fail)\<rbrace>
     deletingIRQHandler irq
   \<lbrace>\<lambda>rv s. isFinal cap slot (cteCaps_of s)\<rbrace>"
  apply (simp add: deletingIRQHandler_def isFinal_def getIRQSlot_def
                   getInterruptState_def locateSlot_conv)
  apply (wp cteDeleteOne_cteCaps_of)
  apply (auto simp: sameObjectAs_def3)
  done

declare suspend_unqueued [wp]

lemma (in delete_one_conc_pre) finaliseCap_replaceable:
  "\<lbrace>\<lambda>s. invs' s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = cap) slot s
       \<and> (final_matters' cap \<longrightarrow> (final = isFinal cap slot (cteCaps_of s)))
       \<and> weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>
     finaliseCap cap final flag
   \<lbrace>\<lambda>rv s. (isNullCap (fst rv) \<and> removeable' slot s cap
                \<and> (\<forall>irq. snd rv = Some irq \<longrightarrow> cap = IRQHandlerCap irq
                                      \<and> isFinal cap slot (cteCaps_of s)))
        \<or>
          (isZombie (fst rv) \<and> snd rv = None
            \<and> isFinal cap slot (cteCaps_of s)
            \<and> capClass cap = capClass (fst rv)
            \<and> capUntypedPtr (fst rv) = capUntypedPtr cap
            \<and> capBits (fst rv) = capBits cap
            \<and> capRange (fst rv) = capRange cap
            \<and> (isThreadCap cap \<or> isCNodeCap cap \<or> isZombie cap)
            \<and> (\<forall>p \<in> threadCapRefs cap. st_tcb_at' (op = Inactive) p s
                     \<and> obj_at' (Not \<circ> tcbQueued) p s
                     \<and> (\<forall>pr. p \<notin> set (ksReadyQueues s pr))))\<rbrace>"
  apply (simp add: finaliseCap_def Let_def getThreadCSpaceRoot
             cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply (wp prepares_delete_helper'' [OF epCancelAll_unlive]
             prepares_delete_helper'' [OF aepCancelAll_unlive]
             suspend_isFinal
             suspend_makes_inactive suspend_nonq
             deletingIRQHandler_removeable'
             deletingIRQHandler_final[where slot=slot]
           | simp add: isZombie_Null isThreadCap_threadCapRefs_tcbptr
                       isArchObjectCap_Cap_capCap
           | (rule hoare_strengthen_post [OF arch_finaliseCap_removeable[where slot=slot]],
                  clarsimp simp: isCap_simps))+
  apply clarsimp
  apply (frule cte_wp_at_valid_objs_valid_cap', clarsimp+)
  apply (case_tac "cteCap cte",
         simp_all add: isCap_simps capRange_def
                       final_matters'_def objBits_simps
                       not_Final_removeable finaliseCap_def,
         simp_all add: removeable'_def)
     (* thread *)
     apply (frule capAligned_capUntypedPtr [OF valid_capAligned], simp)
     apply (clarsimp simp: valid_cap'_def)
     apply (drule valid_globals_cte_wpD'[rotated], clarsimp)
     apply (clarsimp simp: invs'_def valid_state'_def valid_pspace'_def)
    apply (clarsimp | rule conjI)+
  done

crunch cte_wp_at'[wp]: setQueue "\<lambda>s. P (cte_wp_at' P' p s)"

lemma cteDeleteOne_cte_wp_at_preserved:
  assumes x: "\<And>cap final. P cap \<Longrightarrow> finaliseCap cap final True = fail"
  shows "\<lbrace>\<lambda>s. cte_wp_at' (\<lambda>cte. P (cteCap cte)) p s\<rbrace>
           cteDeleteOne ptr
         \<lbrace>\<lambda>rv s. cte_wp_at' (\<lambda>cte. P (cteCap cte)) p s\<rbrace>"
  apply (simp add: tree_cte_cteCap_eq[unfolded o_def])
  apply (rule hoare_pre, wp cteDeleteOne_cteCaps_of)
  apply (clarsimp simp: cteCaps_of_def cte_wp_at_ctes_of x)
  done

crunch ctes_of[wp]: asyncIPCCancel "\<lambda>s. P (ctes_of s)"
  (simp: crunch_simps wp: crunch_wps)

lemma ipcCancel_cteCaps_of:
  "\<lbrace>\<lambda>s. (\<forall>p. cte_wp_at' (\<lambda>cte. \<exists>final. finaliseCap (cteCap cte) final True \<noteq> fail) p s \<longrightarrow>
          P (cteCaps_of s(p \<mapsto> NullCap))) \<and>
     P (cteCaps_of s)\<rbrace>
     ipcCancel t
   \<lbrace>\<lambda>rv s. P (cteCaps_of s)\<rbrace>"
  apply (simp add: ipcCancel_def Let_def capHasProperty_def
                   getThreadReplySlot_def locateSlot_conv)
  apply (rule hoare_pre)
   apply (wp cteDeleteOne_cteCaps_of getCTE_wp' | wpcw
        | simp add: cte_wp_at_ctes_of
        | wp_once hoare_drop_imps ctes_of_cteCaps_of_lift)+
          apply (wp hoare_convert_imp hoare_vcg_all_lift
                    threadSet_ctes_of threadSet_cteCaps_of
               | clarsimp)+
    apply (wp cteDeleteOne_cteCaps_of getCTE_wp' | wpcw | simp
       | wp_once hoare_drop_imps ctes_of_cteCaps_of_lift)+
  apply (clarsimp simp: cte_wp_at_ctes_of cteCaps_of_def)
  apply (drule_tac x="mdbNext (cteMDBNode x)" in spec)
  apply clarsimp
  apply (auto simp: o_def map_option_case fun_upd_def[symmetric])
  done

lemma ipcCancel_cte_wp_at':
  assumes x: "\<And>cap final. P cap \<Longrightarrow> finaliseCap cap final True = fail"
  shows "\<lbrace>\<lambda>s. cte_wp_at' (\<lambda>cte. P (cteCap cte)) p s\<rbrace>
           ipcCancel t
         \<lbrace>\<lambda>rv s. cte_wp_at' (\<lambda>cte. P (cteCap cte)) p s\<rbrace>"
  apply (simp add: tree_cte_cteCap_eq[unfolded o_def])
  apply (rule hoare_pre, wp ipcCancel_cteCaps_of)
  apply (clarsimp simp: cteCaps_of_def cte_wp_at_ctes_of x)
  done

crunch cte_wp_at'[wp]: tcbSchedDequeue "cte_wp_at' P p"

lemma suspend_cte_wp_at':
  assumes x: "\<And>cap final. P cap \<Longrightarrow> finaliseCap cap final True = fail"
  shows "\<lbrace>cte_wp_at' (\<lambda>cte. P (cteCap cte)) p\<rbrace>
           suspend t
         \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>cte. P (cteCap cte)) p\<rbrace>"
  apply (simp add: suspend_def unless_def)
  apply (rule hoare_pre)
   apply (wp threadSet_cte_wp_at' ipcCancel_cte_wp_at'
             | simp add: x)+
  done

crunch cte_wp_at'[wp]: deleteASIDPool "cte_wp_at' P p"
  (simp: crunch_simps assertE_def
         wp: crunch_wps getObject_inv loadObject_default_inv
     ignore: getObject setObject)

lemma deleteASID_cte_wp_at'[wp]:
  "\<lbrace>cte_wp_at' P p\<rbrace> deleteASID param_a param_b \<lbrace>\<lambda>_. cte_wp_at' P p\<rbrace>"
  apply (simp add: deleteASID_def invalidateHWASIDEntry_def invalidateASID_def 
              cong: option.case_cong)
  apply (wp setObject_cte_wp_at'[where Q="\<top>"] getObject_inv
            loadObject_default_inv setVMRoot_cte_wp_at'
          | clarsimp simp: updateObject_default_def in_monad
                           projectKOs
          | rule equals0I
          | wpc)+
  done

crunch cte_wp_at'[wp]: unmapPageTable, unmapPage, finaliseCapTrue_standin
            "cte_wp_at' P p"
  (simp: crunch_simps wp: crunch_wps getObject_inv loadObject_default_inv
     ignore: getObject setObject)

lemma arch_finaliseCap_cte_wp_at[wp]:
  "\<lbrace>cte_wp_at' P p\<rbrace> ArchRetypeDecls_H.finaliseCap cap fin \<lbrace>\<lambda>rv. cte_wp_at' P p\<rbrace>"
  apply (simp add: ArchRetype_H.finaliseCap_def)
  apply (rule hoare_pre)
   apply (wp unmapPage_cte_wp_at'| simp | wpc)+
  done

lemma deletingIRQHandler_cte_preserved:
  assumes x: "\<And>cap final. P cap \<Longrightarrow> finaliseCap cap final True = fail"
  shows "\<lbrace>cte_wp_at' (\<lambda>cte. P (cteCap cte)) p\<rbrace>
           deletingIRQHandler irq
         \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>cte. P (cteCap cte)) p\<rbrace>"
  apply (simp add: deletingIRQHandler_def)
  apply (wp cteDeleteOne_cte_wp_at_preserved
              | simp add: x)+
  done

lemma finaliseCap_equal_cap[wp]:
  "\<lbrace>cte_wp_at' (\<lambda>cte. cteCap cte = cap) sl\<rbrace>
     finaliseCap cap fin flag
   \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>cte. cteCap cte = cap) sl\<rbrace>"
  apply (simp add: finaliseCap_def Let_def
             cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply (wp suspend_cte_wp_at' deletingIRQHandler_cte_preserved
        | clarsimp simp: finaliseCap_def)+
  apply (case_tac cap)
  apply auto
  done

lemma setThreadState_st_tcb_at_simplish':
  "simple' st \<Longrightarrow>
   \<lbrace>st_tcb_at' (P or simple') t\<rbrace>
     setThreadState st t'
   \<lbrace>\<lambda>rv. st_tcb_at' (P or simple') t\<rbrace>"
  apply (wp sts_st_tcb_at'_cases)
  apply clarsimp
  done

lemmas setThreadState_st_tcb_at_simplish
    = setThreadState_st_tcb_at_simplish'[unfolded pred_disj_def]

crunch st_tcb_at_simplish: cteDeleteOne
            "st_tcb_at' (\<lambda>st. P st \<or> simple' st) t"
  (wp: crunch_wps simp: crunch_simps unless_def)

lemma cteDeleteOne_st_tcb_at[wp]:
  assumes x[simp]: "\<And>st. simple' st \<longrightarrow> P st" shows
  "\<lbrace>st_tcb_at' P t\<rbrace> cteDeleteOne slot \<lbrace>\<lambda>rv. st_tcb_at' P t\<rbrace>"
  apply (subgoal_tac "\<exists>Q. P = (Q or simple')")
   apply (clarsimp simp: pred_disj_def)
   apply (rule cteDeleteOne_st_tcb_at_simplish)
  apply (rule_tac x=P in exI)
  apply (auto intro!: ext)
  done

lemma cteDeleteOne_reply_st_tcb_at:
  "\<lbrace>st_tcb_at' P t and cte_wp_at' (\<lambda>cte. cteCap cte = ReplyCap t' False) slot\<rbrace>
    cteDeleteOne slot
   \<lbrace>\<lambda>rv. st_tcb_at' P t\<rbrace>"
  apply (simp add: cteDeleteOne_def unless_def isFinalCapability_def)
  apply (rule hoare_seq_ext [OF _ getCTE_sp])
  apply (rule hoare_assume_pre)
  apply (clarsimp simp: cte_wp_at_ctes_of when_def isCap_simps
                        Let_def finaliseCapTrue_standin_def)
  apply (intro impI conjI, (wp | simp)+)
  done

crunch sch_act_simple[wp]: cteDeleteOne sch_act_simple
  (wp: crunch_wps ssa_sch_act_simple sts_sch_act_simple
   simp: crunch_simps unless_def
   lift: sch_act_simple_lift)

crunch valid_queues[wp]: setSchedulerAction "Invariants_H.valid_queues"
  (simp: Invariants_H.valid_queues_def)

lemma rescheduleRequired_sch_act_not[wp]:
  "\<lbrace>\<top>\<rbrace> rescheduleRequired \<lbrace>\<lambda>rv. sch_act_not t\<rbrace>"
  apply (simp add: rescheduleRequired_def setSchedulerAction_def)
  apply (wp hoare_post_taut | simp)+
  done

crunch sch_act_not[wp]: cteDeleteOne "sch_act_not t"
  (simp: crunch_simps case_Null_If unless_def
     wp: crunch_wps)

lemma epCancelAll_mapM_x_valid_queues:
  "\<lbrace>Invariants_H.valid_queues and valid_objs' and (\<lambda>s. \<forall>t\<in>set q. tcb_at' t s)\<rbrace>
   mapM_x (\<lambda>t. do
                 y \<leftarrow> setThreadState Structures_H.thread_state.Restart t;
                 tcbSchedEnqueue t
               od) q
   \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  apply (rule_tac R="\<lambda>_ s. (\<forall>t\<in>set q. tcb_at' t s) \<and> valid_objs' s"
               in hoare_post_add)
  apply (rule hoare_pre)
  apply (rule mapM_x_wp')
  apply (rule hoare_name_pre_state)
  apply (wp hoare_vcg_const_Ball_lift
            tcbSchedEnqueue_valid_queues tcbSchedEnqueue_not_st
            sts_valid_queues sts_st_tcb_at'_cases setThreadState_not_st
       | simp
       | ((elim conjE)?, drule (1) bspec, clarsimp elim!: obj_at'_weakenE simp: valid_tcb_state'_def))+
  done

lemma epCancelAll_mapM_x_ksSchedulerAction:
  "\<lbrace>sch_act_simple\<rbrace>
   mapM_x (\<lambda>t. do
                 y \<leftarrow> setThreadState Structures_H.thread_state.Restart t;
                 tcbSchedEnqueue t
               od) q
   \<lbrace>\<lambda>_. sch_act_simple\<rbrace>"
  apply (rule mapM_x_wp_inv)
  apply (wp tcbSchedEnqueue_nosch)
  done

lemma epCancelAll_mapM_x_sch_act:
  "\<lbrace>\<lambda>s. sch_act_wf (ksSchedulerAction s) s\<rbrace>
   mapM_x (\<lambda>t. do
                 y \<leftarrow> setThreadState Structures_H.thread_state.Restart t;
                 tcbSchedEnqueue t
               od) q
   \<lbrace>\<lambda>rv s. sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  apply (rule mapM_x_wp_inv)
  apply (wp)
  apply (clarsimp)
 done

lemma epCancelAll_mapM_x_weak_sch_act:
  "\<lbrace>\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>
   mapM_x (\<lambda>t. do
                 y \<leftarrow> setThreadState Structures_H.thread_state.Restart t;
                 tcbSchedEnqueue t
               od) q
   \<lbrace>\<lambda>rv s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  apply (rule mapM_x_wp_inv)
  apply (wp)
  apply (clarsimp)
  done

lemma epCancelAll_mapM_x_valid_objs':
  "\<lbrace>valid_objs'\<rbrace>
   mapM_x (\<lambda>t. do
                 y \<leftarrow> setThreadState Structures_H.thread_state.Restart t;
                 tcbSchedEnqueue t
               od) q
   \<lbrace>\<lambda>_. valid_objs'\<rbrace>"
apply (wp mapM_x_wp' sts_valid_objs')
apply (clarsimp simp: valid_tcb_state'_def)
done

lemma epCancelAll_mapM_x_tcbDomain_obj_at':
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t'\<rbrace>
   mapM_x (\<lambda>t. do
                 y \<leftarrow> setThreadState Structures_H.thread_state.Restart t;
                 tcbSchedEnqueue t
               od) q
  \<lbrace>\<lambda>_. obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t'\<rbrace>"
apply (wp mapM_x_wp' tcbSchedEnqueue_not_st setThreadState_oa_queued | simp)+
done

lemma rescheduleRequired_oa_queued':
  "\<lbrace>obj_at' (\<lambda>tcb. Q (tcbDomain tcb) (tcbPriority tcb)) t'\<rbrace>
    rescheduleRequired
   \<lbrace>\<lambda>_. obj_at' (\<lambda>tcb. Q (tcbDomain tcb) (tcbPriority tcb)) t'\<rbrace>"
apply (simp add: rescheduleRequired_def)
apply (wp tcbSchedEnqueue_not_st
     | wpc
     | simp)+
done

lemma epCancelAll_tcbDomain_obj_at':
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t'\<rbrace>
     epCancelAll epptr
   \<lbrace>\<lambda>_. obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t'\<rbrace>"
apply (simp add: epCancelAll_def)
apply (wp hoare_vcg_conj_lift hoare_vcg_const_Ball_lift
          rescheduleRequired_oa_queued' epCancelAll_mapM_x_tcbDomain_obj_at' epCancelAll_mapM_x_ksSchedulerAction
          getEndpoint_wp
     | wpc
     | simp)+
done

lemma epCancelAll_valid_queues[wp]:
  "\<lbrace>Invariants_H.valid_queues and valid_objs' and (\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s)\<rbrace>
   epCancelAll ep_ptr
   \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  apply (simp add: epCancelAll_def ep'_Idle_case_helper)
  apply (wp hoare_vcg_conj_lift hoare_vcg_const_Ball_lift
            epCancelAll_mapM_x_valid_queues epCancelAll_mapM_x_valid_objs' epCancelAll_mapM_x_weak_sch_act
            set_ep_valid_objs' getEndpoint_wp)
  apply (clarsimp simp: valid_ep'_def)
  apply (drule (1) ko_at_valid_objs')
  apply (auto simp: valid_obj'_def valid_ep'_def valid_tcb'_def projectKOs
             split: endpoint.splits
              elim: valid_objs_valid_tcbE)
  done

lemma aepCancelAll_tcbDomain_obj_at':
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t'\<rbrace>
     aepCancelAll epptr
   \<lbrace>\<lambda>_. obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t'\<rbrace>"
apply (simp add: aepCancelAll_def)
apply (wp hoare_vcg_conj_lift hoare_vcg_const_Ball_lift
          rescheduleRequired_oa_queued' epCancelAll_mapM_x_tcbDomain_obj_at' epCancelAll_mapM_x_ksSchedulerAction
          getAsyncEP_wp
     | wpc
     | simp)+
done

lemma aepCancelAll_valid_queues[wp]:
  "\<lbrace>Invariants_H.valid_queues and valid_objs' and (\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s)\<rbrace>
   aepCancelAll aep
   \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  apply (simp add: aepCancelAll_def)
  apply (rule hoare_seq_ext [OF _ get_aep_sp'])
  apply (case_tac aepa, simp_all)
    apply (wp, simp)+
   apply (rule hoare_pre)
    apply (wp hoare_vcg_conj_lift hoare_vcg_const_Ball_lift
              epCancelAll_mapM_x_valid_queues epCancelAll_mapM_x_valid_objs' epCancelAll_mapM_x_weak_sch_act
              set_aep_valid_objs'
          | simp)+
  apply (clarsimp simp: valid_ep'_def)
  apply (drule (1) ko_at_valid_objs')
  apply (auto simp: valid_obj'_def valid_aep'_def valid_tcb'_def projectKOs
             split: endpoint.splits
              elim: valid_objs_valid_tcbE)
  done

lemma finaliseCap_True_valid_queues[wp]:
  "\<lbrace> Invariants_H.valid_queues and valid_objs' and (\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s)\<rbrace>
   finaliseCap cap final True
   \<lbrace>\<lambda>_. Invariants_H.valid_queues \<rbrace>"
  apply (simp add: finaliseCap_def Let_def)
  apply safe 
    apply (wp irqs_masked_lift| simp)+
  done

lemma finaliseCapTrue_standin_valid_queues[wp]:
  "\<lbrace>Invariants_H.valid_queues and valid_objs' and (\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s)\<rbrace>
   finaliseCapTrue_standin cap final
   \<lbrace>\<lambda>_. Invariants_H.valid_queues\<rbrace>"
  apply (simp add: finaliseCapTrue_standin_def)
  apply (safe)
       apply (wp | clarsimp)+
  done

crunch valid_queues[wp]: isFinalCapability "Invariants_H.valid_queues"
  (simp: crunch_simps)

crunch sch_act[wp]: isFinalCapability "\<lambda>s. sch_act_wf (ksSchedulerAction s) s"
  (simp: crunch_simps)
crunch weak_sch_act[wp]:
  isFinalCapability "\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s"
  (simp: crunch_simps)

lemma cteDeleteOne_queues[wp]:
  "\<lbrace>Invariants_H.valid_queues and valid_objs' and (\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s)\<rbrace>
   cteDeleteOne sl
   \<lbrace>\<lambda>_. Invariants_H.valid_queues\<rbrace>" (is "\<lbrace>?PRE\<rbrace> _ \<lbrace>_\<rbrace>")
  apply (simp add: cteDeleteOne_def unless_def split_def)
  apply (wp isFinalCapability_inv getCTE_wp | rule hoare_drop_imps | simp)+
  apply (clarsimp simp: cte_wp_at'_def)
  done

lemma valid_inQ_queues_lift:
  assumes tat: "\<And>d p tcb. \<lbrace>obj_at' (inQ d p) tcb\<rbrace> f \<lbrace>\<lambda>_. obj_at' (inQ d p) tcb\<rbrace>"
  and     prq: "\<And>P. \<lbrace>\<lambda>s. P (ksReadyQueues s)\<rbrace> f \<lbrace>\<lambda>_ s. P (ksReadyQueues s)\<rbrace>"
  shows   "\<lbrace>valid_inQ_queues\<rbrace> f \<lbrace>\<lambda>_. valid_inQ_queues\<rbrace>"
  proof -
    show ?thesis
      apply (clarsimp simp: valid_def valid_inQ_queues_def)
      apply safe
       apply (rule use_valid [OF _ tat], assumption)
       apply (drule spec, drule spec, erule conjE, erule bspec)
       apply (rule ccontr)
       apply (erule notE[rotated], erule(1) use_valid [OF _ prq])
      apply (erule use_valid [OF _ prq])
      apply simp
      done
  qed

lemma emptySlot_valid_inQ_queues [wp]:
  "\<lbrace>valid_inQ_queues\<rbrace> emptySlot sl opt \<lbrace>\<lambda>rv. valid_inQ_queues\<rbrace>"
  unfolding emptySlot_def
  by (wp opt_return_pres_lift | wpcw | wp valid_inQ_queues_lift | simp)+

crunch valid_inQ_queues[wp]: emptySlot valid_inQ_queues
  (simp: crunch_simps ignore: updateObject setObject)

lemma epCancelAll_mapM_x_valid_inQ_queues:
  "\<lbrace>valid_inQ_queues\<rbrace>
   mapM_x (\<lambda>t. do
                 y \<leftarrow> setThreadState Structures_H.thread_state.Restart t;
                 tcbSchedEnqueue t
               od) q
   \<lbrace>\<lambda>rv. valid_inQ_queues\<rbrace>"
  apply (rule mapM_x_wp_inv)
  apply (wp sts_valid_queues [where st="Structures_H.thread_state.Restart", simplified]
            setThreadState_st_tcb)
   done

lemma epCancelAll_valid_inQ_queues[wp]:
  "\<lbrace>valid_inQ_queues\<rbrace>
   epCancelAll ep_ptr
   \<lbrace>\<lambda>rv. valid_inQ_queues\<rbrace>"
  apply (simp add: epCancelAll_def ep'_Idle_case_helper)
  apply (wp epCancelAll_mapM_x_valid_inQ_queues)
  apply (wp hoare_conjI hoare_drop_imp | simp)+
  done

lemma aepCancelAll_valid_inQ_queues[wp]:
  "\<lbrace>valid_inQ_queues\<rbrace>
   aepCancelAll aep
   \<lbrace>\<lambda>rv. valid_inQ_queues\<rbrace>"
  apply (simp add: aepCancelAll_def)
  apply (rule hoare_seq_ext [OF _ get_aep_sp'])
  apply (case_tac aepa, simp_all)
    apply (wp, simp)+
   apply (rule hoare_pre)
    apply (wp epCancelAll_mapM_x_valid_inQ_queues)
   apply (simp)
  apply (wp)
   apply (clarsimp)+
  done

lemma finaliseCapTrue_standin_valid_inQ_queues[wp]:
  "\<lbrace>valid_inQ_queues\<rbrace>
   finaliseCapTrue_standin cap final
   \<lbrace>\<lambda>_. valid_inQ_queues\<rbrace>"
  apply (simp add: finaliseCapTrue_standin_def)
  apply (safe)
       apply (wp | clarsimp)+
  done

crunch valid_inQ_queues[wp]: isFinalCapability valid_inQ_queues
  (simp: crunch_simps)

lemma cteDeleteOne_valid_inQ_queues[wp]:
  "\<lbrace>valid_inQ_queues\<rbrace>
   cteDeleteOne sl
   \<lbrace>\<lambda>_. valid_inQ_queues\<rbrace>"
  apply (simp add: cteDeleteOne_def unless_def)
  apply (wp)
     apply (clarsimp)
     apply (wp)
     apply (fastforce)
    apply (wp)
  apply (clarsimp)
  apply (wp)
  done

crunch ksCurDomain[wp]: cteDeleteOne "\<lambda>s. P (ksCurDomain s)"
  (wp: crunch_wps simp: crunch_simps unless_def)

lemma cteDeleteOne_tcbDomain_obj_at':
  "\<lbrace>obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t'\<rbrace> cteDeleteOne slot \<lbrace>\<lambda>_. obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t'\<rbrace>"
apply (simp add: cteDeleteOne_def unless_def split_def)
apply (wp emptySlot_tcbDomain epCancelAll_tcbDomain_obj_at' aepCancelAll_tcbDomain_obj_at'
          isFinalCapability_inv getCTE_wp
     | rule hoare_drop_imp
     | simp add: finaliseCapTrue_standin_def
            split del: if_splits)+
apply (clarsimp simp: cte_wp_at'_def)
done

interpretation delete_one_conc_pre
  by unfold_locales (wp cteDeleteOne_tcbDomain_obj_at' | simp)+

lemma cteDeleteOne_invs[wp]:
  "\<lbrace>invs'\<rbrace> cteDeleteOne ptr \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: cteDeleteOne_def unless_def
                   split_def finaliseCapTrue_standin_simple_def)
  apply wp
    apply (rule hoare_strengthen_post)
     apply (rule hoare_vcg_conj_lift) 
      apply (rule finaliseCap_True_invs)
     apply (rule hoare_vcg_conj_lift)
      apply (rule finaliseCap_replaceable[where slot=ptr])
     apply (rule hoare_vcg_conj_lift)
      apply (rule finaliseCap_cte_refs)
     apply (rule finaliseCap_equal_cap[where sl=ptr])
    apply (clarsimp simp: cte_wp_at_ctes_of)
    apply (erule disjE)
     apply simp
    apply (clarsimp dest!: isCapDs simp: capRemovable_def)
    apply (clarsimp simp: removeable'_def fun_eq_iff[where f="cte_refs' cap" for cap]
                     del: disjCI)
    apply (rule disjI2)
    apply (rule conjI)
     apply auto[1]
    apply (auto dest!: isCapDs simp: st_tcb_at'_def obj_at'_def projectKOs
                                     ko_wp_at'_def)[1]
   apply (wp isFinalCapability_inv static_imp_wp)
    apply (wp_once isFinal[where x=ptr])
   apply (wp isFinalCapability_inv getCTE_wp')
  apply (fastforce simp: cte_wp_at_ctes_of)
  done

interpretation delete_one_conc_fr: delete_one_conc
  by unfold_locales (wp, simp)

declare cteDeleteOne_invs[wp]

lemma deletingIRQHandler_invs' [wp]:
  "\<lbrace>invs'\<rbrace> deletingIRQHandler i \<lbrace>\<lambda>_. invs'\<rbrace>"
  by (simp add: deletingIRQHandler_def) wp

lemma finaliseCap_invs:
  "\<lbrace>invs' and sch_act_simple and valid_cap' cap
         and cte_wp_at' (\<lambda>cte. cteCap cte = cap) sl\<rbrace>
     finaliseCap cap fin flag
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: finaliseCap_def Let_def
             cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply (wp | simp only: o_def)+
  apply clarsimp
  apply (intro conjI impI)
    apply (clarsimp dest!: isCapDs simp: valid_cap'_def)
   apply (drule invs_valid_global', drule(1) valid_globals_cte_wpD')
   apply (drule valid_capAligned, drule capAligned_capUntypedPtr)
    apply (clarsimp dest!: isCapDs)
   apply (clarsimp dest!: isCapDs)
  apply (clarsimp dest!: isCapDs)
  done

lemma finaliseCap_zombie_cap[wp]:
  "\<lbrace>cte_wp_at' (\<lambda>cte. (P and isZombie) (cteCap cte)) sl\<rbrace>
     finaliseCap cap fin flag
   \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>cte. (P and isZombie) (cteCap cte)) sl\<rbrace>"
  apply (simp add: finaliseCap_def Let_def
             cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply (wp suspend_cte_wp_at'
             deletingIRQHandler_cte_preserved
                 | clarsimp simp: finaliseCap_def isCap_simps)+
  done

lemma finaliseCap_zombie_cap':
  "\<lbrace>cte_wp_at' (\<lambda>cte. (P and isZombie) (cteCap cte)) sl\<rbrace>
     finaliseCap cap fin flag
   \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>cte. P (cteCap cte)) sl\<rbrace>"
  apply (rule hoare_strengthen_post)
   apply (rule finaliseCap_zombie_cap)
  apply (clarsimp simp: cte_wp_at_ctes_of)
  done

lemma finaliseCap_cte_cap_wp_to[wp]:
  "\<lbrace>ex_cte_cap_wp_to' P sl\<rbrace> finaliseCap cap fin flag \<lbrace>\<lambda>rv. ex_cte_cap_wp_to' P sl\<rbrace>"
  apply (simp add: ex_cte_cap_to'_def)
  apply (rule hoare_pre, rule hoare_use_eq_irq_node' [OF finaliseCap_irq_node'])
   apply (simp add: finaliseCap_def Let_def
              cong: if_cong split del: split_if)
   apply (wp suspend_cte_wp_at'
             deletingIRQHandler_cte_preserved
             hoare_vcg_ex_lift
                 | clarsimp simp: finaliseCap_def isCap_simps
                 | rule conjI)+
  apply fastforce
  done

lemma finaliseCap_valid_cap[wp]:
  "\<lbrace>valid_cap' cap\<rbrace> finaliseCap cap final flag \<lbrace>\<lambda>rv. valid_cap' (fst rv)\<rbrace>"
  apply (simp add: finaliseCap_def Let_def
                   getThreadCSpaceRoot
                   ArchRetype_H.finaliseCap_def
             cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply (wp | simp only: valid_NullCap o_def fst_conv | wpc)+
  apply simp
  apply (intro conjI impI)
   apply (clarsimp simp: valid_cap'_def isCap_simps capAligned_def
                         objBits_simps shiftL_nat)+
  done

crunch nosch[wp]: "ArchRetypeDecls_H.finaliseCap" "\<lambda>s. P (ksSchedulerAction s)"
  (wp: crunch_wps getObject_inv simp: loadObject_default_def updateObject_default_def
   ignore: getObject)

crunch sch_act_simple[wp]: finaliseCap sch_act_simple
  (simp: crunch_simps 
   lift: sch_act_simple_lift)

lemma (in delete_one) deleting_irq_corres:
  "corres dc (einvs) (invs' and sch_act_simple) 
          (deleting_irq_handler irq) (deletingIRQHandler irq)"
  apply (simp add: deleting_irq_handler_def deletingIRQHandler_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ get_irq_slot_corres])
      apply simp
      apply (rule delete_one_corres)
     apply (wp | simp)+
  done

lemma arch_finalise_cap_corres:
  "\<lbrakk> final_matters' (ArchObjectCap cap') \<Longrightarrow> final = final'; acap_relation cap cap' \<rbrakk>
     \<Longrightarrow> corres cap_relation
           (\<lambda>s. invs s \<and> valid_etcbs s
                       \<and> s \<turnstile> cap.ArchObjectCap cap
                       \<and> (final_matters (cap.ArchObjectCap cap)
                            \<longrightarrow> final = is_final_cap' (cap.ArchObjectCap cap) s)
                       \<and> cte_wp_at (op = (cap.ArchObjectCap cap)) sl s)
           (\<lambda>s. invs' s \<and> s \<turnstile>' ArchObjectCap cap' \<and>
                 (final_matters' (ArchObjectCap cap') \<longrightarrow>
                      final' = isFinal (ArchObjectCap cap') (cte_map sl) (cteCaps_of s)))
           (arch_finalise_cap cap final) (ArchRetypeDecls_H.finaliseCap cap' final')"
  apply (cases cap,
         simp_all add: arch_finalise_cap_def ArchRetype_H.finaliseCap_def
                       final_matters'_def case_bool_If liftM_def[symmetric]
                       o_def dc_def[symmetric]
                split: option.split,
         safe)
     apply (rule corres_guard_imp, rule delete_asid_pool_corres)
      apply (clarsimp simp: valid_cap_def mask_def)
     apply (clarsimp simp: valid_cap'_def)
     apply auto[1]
    apply (rule corres_guard_imp, rule unmap_page_corres)
      apply simp
     apply (clarsimp simp: valid_cap_def valid_unmap_def)
     apply (auto simp: vmsz_aligned_def pbfs_atleast_pageBits mask_def
                 elim: is_aligned_weaken invs_valid_asid_map)[2]
   apply (rule corres_guard_imp, rule unmap_page_table_corres)
    apply (auto simp: valid_cap_def valid_cap'_def mask_def
               elim!: is_aligned_weaken invs_valid_asid_map)[2]
  apply (rule corres_guard_imp, rule delete_asid_corres)
   apply (auto elim!: invs_valid_asid_map simp: mask_def valid_cap_def)[2]
  done

lemma fast_finalise_corres:
  "\<lbrakk> final_matters' cap' \<longrightarrow> final = final'; cap_relation cap cap';
     can_fast_finalise cap \<rbrakk>
   \<Longrightarrow> corres dc
           (\<lambda>s. invs s \<and> valid_sched s \<and> s \<turnstile> cap
                       \<and> cte_wp_at (op = cap) sl s)
           (\<lambda>s. invs' s \<and> s \<turnstile>' cap')
           (fast_finalise cap final)
           (do
               p \<leftarrow> finaliseCap cap' final' True;
               assert (capRemovable (fst p) (cte_map ptr) \<and> snd p = None)
            od)"
  apply (cases cap, simp_all add: finaliseCap_def isCap_simps
                                  corres_liftM2_simp[unfolded liftM_def]
                                  o_def dc_def[symmetric] when_def
                                  can_fast_finalise_def capRemovable_def
                       split del: split_if cong: if_cong)
   apply (clarsimp simp: final_matters'_def)
   apply (rule corres_guard_imp)
     apply (rule corres_rel_imp)
      apply (rule ep_cancel_corres)
     apply simp
    apply (simp add: valid_cap_def)
   apply (simp add: valid_cap'_def)
  apply (clarsimp simp: final_matters'_def)
  apply (rule corres_guard_imp)
    apply (rule corres_rel_imp)
     apply (rule aep_cancel_corres)
    apply simp
   apply (simp add: valid_cap_def)
  apply (simp add: valid_cap'_def)
  done

lemma cap_delete_one_corres:
  "corres dc (einvs and cte_wp_at can_fast_finalise ptr)
        (invs' and cte_at' (cte_map ptr))
        (cap_delete_one ptr) (cteDeleteOne (cte_map ptr))" 
  apply (simp add: cap_delete_one_def cteDeleteOne_def'
                   unless_def when_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ get_cap_corres])
      apply (rule_tac F="can_fast_finalise cap" in corres_gen_asm)
      apply (rule corres_if)
        apply fastforce
       apply (rule corres_split [OF _ final_cap_corres[where ptr=ptr]])
         apply (simp add: split_def bind_assoc [THEN sym])
         apply (rule corres_split [OF _ fast_finalise_corres[where sl=ptr]])
              apply (rule empty_slot_corres)
             apply simp+
          apply (wp hoare_drop_imps)
        apply (wp isFinalCapability_inv | wp_once isFinal[where x="cte_map ptr"])+
      apply (rule corres_trivial, simp)
     apply (wp get_cap_wp getCTE_wp)
   apply (clarsimp simp: cte_wp_at_caps_of_state can_fast_finalise_Null
                  elim!: caps_of_state_valid_cap)
  apply (clarsimp simp: cte_wp_at_ctes_of)
  apply fastforce
  done

(* FIXME: strengthen locale instead *)

interpretation delete_one
  apply unfold_locales
  apply (rule corres_guard_imp)
    apply (rule cap_delete_one_corres)
   apply auto
  done

lemma finalise_cap_corres:
  "\<lbrakk> final_matters' cap' \<Longrightarrow> final = final'; cap_relation cap cap';
          flag \<longrightarrow> can_fast_finalise cap \<rbrakk>
     \<Longrightarrow> corres (\<lambda>x y. cap_relation (fst x) (fst y) \<and> snd x = snd y)
           (\<lambda>s. einvs s \<and> s \<turnstile> cap \<and> (final_matters cap \<longrightarrow> final = is_final_cap' cap s)
                       \<and> cte_wp_at (op = cap) sl s)
           (\<lambda>s. invs' s \<and> sch_act_simple s \<and> s \<turnstile>' cap' \<and>
                 (final_matters' cap' \<longrightarrow>
                      final' = isFinal cap' (cte_map sl) (cteCaps_of s)))
           (finalise_cap cap final) (finaliseCap cap' final' flag)"
  apply (cases cap, simp_all add: finaliseCap_def isCap_simps
                                  corres_liftM2_simp[unfolded liftM_def]
                                  o_def dc_def[symmetric] when_def
                                  can_fast_finalise_def
                       split del: split_if cong: if_cong)
        apply (clarsimp simp: final_matters'_def)
        apply (rule corres_guard_imp)
          apply (rule ep_cancel_corres)
         apply (simp add: valid_cap_def)
        apply (simp add: valid_cap'_def)
       apply (clarsimp simp add: final_matters'_def)
       apply (rule corres_guard_imp)
         apply (rule aep_cancel_corres)
        apply (simp add: valid_cap_def)
       apply (simp add: valid_cap'_def)
      apply (fastforce simp: final_matters'_def shiftL_nat zbits_map_def)
     apply (clarsimp simp add: final_matters'_def getThreadCSpaceRoot
                               liftM_def[symmetric] o_def zbits_map_def
                               dc_def[symmetric])
     apply (rule corres_guard_imp)
       apply (rule suspend_corres)
      apply (simp add: valid_cap_def)
     apply (simp add: valid_cap'_def)
    apply (simp add: final_matters'_def liftM_def[symmetric]
                     o_def dc_def[symmetric])
    apply (intro impI, rule corres_guard_imp)
      apply (rule deleting_irq_corres)
     apply simp
    apply simp
   apply (clarsimp simp: final_matters'_def)
   apply (rule_tac F="False" in corres_req)
    apply clarsimp
    apply (frule zombies_finalD, (clarsimp simp: is_cap_simps)+)
    apply (clarsimp simp: cte_wp_at_caps_of_state)
   apply simp
  apply (clarsimp split del: split_if simp: o_def)
  apply (rule corres_guard_imp [OF arch_finalise_cap_corres], (fastforce simp: valid_sched_def)+)
  done

lemma arch_recycleCap_improve_cases:
   "\<lbrakk> \<not> isPageCap cap; \<not> isPageTableCap cap; \<not> isPageDirectoryCap cap;
         \<not> isASIDControlCap cap \<rbrakk> \<Longrightarrow> (if isASIDPoolCap cap then v else undefined) = v"
  by (cases cap, simp_all add: isCap_simps)

crunch queues[wp]: copyGlobalMappings "Invariants_H.valid_queues"
  (wp: crunch_wps ignore: storePDE getObject)

crunch queues'[wp]: copyGlobalMappings "Invariants_H.valid_queues'"
  (wp: crunch_wps ignore: storePDE getObject)

crunch ifunsafe'[wp]: copyGlobalMappings "if_unsafe_then_cap'"
  (wp: crunch_wps ignore: storePDE getObject)

lemma copyGlobalMappings_pde_mappings2':
  "\<lbrace>valid_pde_mappings' and valid_arch_state'
            and K (is_aligned pd pdBits)\<rbrace>
      copyGlobalMappings pd \<lbrace>\<lambda>rv. valid_pde_mappings'\<rbrace>"
  apply (wp copyGlobalMappings_pde_mappings')
  apply (clarsimp simp: valid_arch_state'_def page_directory_at'_def)
  done

crunch st_tcb_at'[wp]: copyGlobalMappings "st_tcb_at' P t"
  (wp: crunch_wps ignore: storePDE getObject)

crunch vms'[wp]: copyGlobalMappings "valid_machine_state'"
  (wp: crunch_wps ignore: storePDE getObject)

crunch ct_not_inQ[wp]: copyGlobalMappings "ct_not_inQ"
  (wp: crunch_wps ignore: storePDE getObject)

crunch tcb_in_cur_domain'[wp]: copyGlobalMappings "tcb_in_cur_domain' t"
  (wp: crunch_wps ignore: getObject)

crunch ct__in_cur_domain'[wp]: copyGlobalMappings ct_idle_or_in_cur_domain'
  (wp: crunch_wps ignore: getObject)

lemma copyGlobalMappings_invs'[wp]:
  "\<lbrace>invs' and K (is_aligned pd pdBits)\<rbrace> copyGlobalMappings pd \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: invs'_def valid_state'_def valid_pspace'_def)
  apply (wp valid_irq_node_lift_asm valid_global_refs_lift' sch_act_wf_lift
            valid_irq_handlers_lift'' cur_tcb_lift typ_at_lifts irqs_masked_lift
            copyGlobalMappings_pde_mappings2'
       | clarsimp)+
  done

lemma dmo'_bind_return:
  "\<lbrace>P\<rbrace> doMachineOp f \<lbrace>\<lambda>_. Q\<rbrace> \<Longrightarrow>
   \<lbrace>P\<rbrace> doMachineOp (do _ \<leftarrow> f; return x od) \<lbrace>\<lambda>_. Q\<rbrace>"
  by (clarsimp simp: doMachineOp_def bind_def return_def valid_def select_f_def
                     split_def)

lemma clearMemory_vms':
  "valid_machine_state' s \<Longrightarrow>
   \<forall>x\<in>fst (clearMemory ptr bits (ksMachineState s)).
      valid_machine_state' (s\<lparr>ksMachineState := snd x\<rparr>)"
  apply (clarsimp simp: valid_machine_state'_def
                        disj_commute[of "pointerInUserData p s" for p s])
  apply (drule_tac x=p in spec, simp)
  apply (drule_tac P4="\<lambda>m'. underlying_memory m' p = 0"
         in use_valid[where P=P and Q="\<lambda>_. P" for P], simp_all)
  apply (rule clearMemory_um_eq_0)
  done

lemma ct_not_inQ_ksMachineState_update[simp]:
  "ct_not_inQ (s\<lparr>ksMachineState := v\<rparr>) = ct_not_inQ s"
  by (simp add: ct_not_inQ_def)

lemma ct_in_current_domain_ksMachineState_update[simp]:
  "ct_idle_or_in_cur_domain' (s\<lparr>ksMachineState := v\<rparr>) = ct_idle_or_in_cur_domain' s"
  by (simp add: ct_idle_or_in_cur_domain'_def tcb_in_cur_domain'_def)

lemma dmo_clearMemory_invs'[wp]:
  "\<lbrace>invs'\<rbrace> doMachineOp (clearMemory w sz) \<lbrace>\<lambda>_. invs'\<rbrace>"
  apply (simp add: doMachineOp_def split_def)
  apply wp
  apply (clarsimp simp: invs'_def valid_state'_def)
  apply (rule conjI)
   apply (simp add: valid_irq_masks'_def, elim allEI, clarsimp)
   apply (drule use_valid)
     apply (rule no_irq_clearMemory[simplified no_irq_def, rule_format])
    apply simp_all
  apply (drule clearMemory_vms')
  apply fastforce
  done

lemma ct_in_current_domain_ArchState_update[simp]:
  "ct_idle_or_in_cur_domain' (s\<lparr>ksArchState := v\<rparr>) = ct_idle_or_in_cur_domain' s"
  by (simp add: ct_idle_or_in_cur_domain'_def tcb_in_cur_domain'_def)

lemma arch_recycleCap_invs:
  "\<lbrace>cte_wp_at' (\<lambda>cte. cteCap cte = ArchObjectCap cap) slot and invs'\<rbrace>
     ArchRetypeDecls_H.recycleCap is_final cap
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: ArchRetype_H.recycleCap_def arch_recycleCap_improve_cases
                   Let_def
              split del: split_if)
  apply (rule hoare_pre)
   apply (wp dmo'_bind_return
             pageTableMapped_invs' mapM_x_storePTE_invs mapM_x_wp' 
             storePTE_typ_ats storePDE_typ_ats          
          | wpc | simp | simp add: eq_commute invalidateTLBByASID_def)+
      apply (rule hoare_post_imp
                  [where Q="\<lambda>rv s. invs' s \<and> s \<turnstile>' capability.ArchObjectCap cap"])
       apply (wp dmo'_bind_return
                 pageTableMapped_invs' mapM_x_storePTE_invs mapM_x_wp' 
                 storePTE_typ_ats storePDE_typ_ats static_imp_wp
              | wpc | simp | simp add: eq_commute invalidateTLBByASID_def)+
      apply (rule hoare_post_imp_R
                  [where Q'="\<lambda>rv s. invs' s \<and> s \<turnstile>' capability.ArchObjectCap cap"])
       apply (wp dmo'_bind_return
                 pageTableMapped_invs' mapM_x_storePTE_invs mapM_x_wp' 
                 storePTE_typ_ats storePDE_typ_ats static_imp_wp
              | wpc | simp | simp add: eq_commute invalidateTLBByASID_def)+
     apply (rule_tac Q="\<lambda>rv. invs' and asid_pool_at' (capASIDPool cap)"
       in hoare_post_imp)
      apply (cases cap, simp_all add: isCap_simps)[1]
      apply (clarsimp simp: invs'_def valid_state'_def)
      apply (intro conjI)
        apply (simp add: valid_global_refs'_def global_refs'_def)
       apply (simp add: valid_arch_state'_def valid_asid_table'_def
                        fun_upd_def[symmetric])
       apply (clarsimp simp: ran_def valid_pspace'_def)
       apply (rule conjI, blast)
       apply clarsimp
      apply (simp add: valid_machine_state'_def)
     apply wp
    apply (simp add: makeObject_asidpool)
    apply wp
  apply clarsimp
  apply (drule cte_wp_at_valid_objs_valid_cap', clarsimp+)
  apply (clarsimp simp: valid_cap'_def page_directory_at'_def
                  split: arch_capability.splits option.splits
                  elim!: ranE,
         simp_all add: isCap_simps)
  done

lemma threadSet_ct_idle_or_in_cur_domain':
  "\<lbrace>ct_idle_or_in_cur_domain' and (\<lambda>s. \<forall>tcb. tcbDomain tcb = ksCurDomain s \<longrightarrow> tcbDomain (F tcb) = ksCurDomain s)\<rbrace>
    threadSet F t
   \<lbrace>\<lambda>_. ct_idle_or_in_cur_domain'\<rbrace>"
apply (simp add: ct_idle_or_in_cur_domain'_def tcb_in_cur_domain'_def)
apply (wp hoare_vcg_disj_lift hoare_vcg_imp_lift)
  apply wps
  apply wp
 apply wps
 apply wp
apply (auto simp: obj_at'_def)
done

lemma recycleCap_invs:
  "\<lbrace>cte_wp_at' (\<lambda>cte. cteCap cte = cap) slot and invs' and sch_act_simple\<rbrace>
     recycleCap is_final cap
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: recycleCap_def split del: split_if)
  apply (cases cap, simp_all add: isCap_simps)
            defer 6 (* Zombie *)
            apply ((wp arch_recycleCap_invs [where slot=slot] | simp)+)[10]
  apply (rename_tac word zombie_type nat)
  apply (case_tac zombie_type, simp_all add: threadGet_def curDomain_def)
   apply (rule hoare_seq_ext [OF _ assert_sp]
               hoare_seq_ext [OF _ getObject_tcb_sp]
               hoare_seq_ext [OF _ gets_sp])+
   apply (rule hoare_name_pre_state)
   apply (clarsimp simp: invs'_def valid_state'_def
                  split: thread_state.split_asm split del: split_if)
   apply (wp
             threadSet_valid_pspace'T_P[where P=False, simplified]
             threadSet_sch_act_wf
             threadSet_valid_queues
             threadSet_valid_queues_Qf[where Qf=id]
             threadSet_state_refs_of'T_P[where f'=id and P'=True and Q="op = Inactive", simplified]
             threadSet_iflive'T
             threadSet_ifunsafe'T
             threadSet_idle'T
             threadSet_global_refsT
             threadSet_cur
             valid_irq_node_lift
             valid_irq_handlers_lift''
             threadSet_ctes_ofT
             irqs_masked_lift
             threadSet_not_inQ
             threadSet_ct_idle_or_in_cur_domain'
             threadSet_valid_dom_schedule'
             threadSet_ct_idle_or_in_cur_domain'
        | simp add: tcb_cte_cases_def makeObject_tcb valid_tcb_state'_def minBound_word)+
                 apply (auto simp: ksReadyQueues_update_id inQ_def addToQs_def obj_at'_def st_tcb_at'_def makeObject_tcb projectKOs objBits_simps ct_in_state'_def)[15]
  apply wp
  apply simp
  done

crunch typ_at'[wp]: invalidateTLBByASID "\<lambda>s. P (typ_at' T p s)"
crunch valid_arch_state'[wp]: invalidateTLBByASID "valid_arch_state'"
lemmas invalidateTLBByASID_typ_ats[wp] = typ_at_lifts [OF invalidateTLBByASID_typ_at']

lemma cte_wp_at_norm_eq':
  "cte_wp_at' P p s = (\<exists>cte. cte_wp_at' (op = cte) p s \<and> P cte)"
  by (simp add: cte_wp_at_ctes_of)

lemma isFinal_cte_wp_def:
  "isFinal cap p (cteCaps_of s) =
  (\<not>isUntypedCap cap \<and>
   (\<forall>p'. p \<noteq> p' \<longrightarrow> 
         cte_at' p' s \<longrightarrow>
         cte_wp_at' (\<lambda>cte'. \<not> isUntypedCap (cteCap cte') \<longrightarrow>  
                            \<not> sameObjectAs cap (cteCap cte')) p' s))"
  apply (simp add: isFinal_def cte_wp_at_ctes_of cteCaps_of_def)
  apply (rule iffI)
   apply clarsimp
   apply (case_tac cte)
   apply fastforce
  apply fastforce
  done

lemma valid_cte_at_neg_typ':
  assumes T: "\<And>P T p. \<lbrace>\<lambda>s. P (typ_at' T p s)\<rbrace> f \<lbrace>\<lambda>_ s. P (typ_at' T p s)\<rbrace>"
  shows "\<lbrace>\<lambda>s. \<not> cte_at' p' s\<rbrace> f \<lbrace>\<lambda>rv s. \<not> cte_at' p' s\<rbrace>"
  apply (simp add: cte_at_typ')
  apply (rule hoare_vcg_conj_lift [OF T])
  apply (simp only: imp_conv_disj)
  apply (rule hoare_vcg_all_lift)
  apply (rule hoare_vcg_disj_lift [OF T])
  apply (rule hoare_vcg_prop)
  done

lemma isFinal_lift:
  assumes x: "\<And>P p. \<lbrace>cte_wp_at' P p\<rbrace> f \<lbrace>\<lambda>_. cte_wp_at' P p\<rbrace>"
  assumes y: "\<And>P T p. \<lbrace>\<lambda>s. P (typ_at' T p s)\<rbrace> f \<lbrace>\<lambda>_ s. P (typ_at' T p s)\<rbrace>"
  shows "\<lbrace>\<lambda>s. cte_wp_at' (\<lambda>cte. isFinal (cteCap cte) sl (cteCaps_of s)) sl s\<rbrace> 
         f 
         \<lbrace>\<lambda>r s. cte_wp_at' (\<lambda>cte. isFinal (cteCap cte) sl (cteCaps_of s)) sl s\<rbrace>"
  apply (subst cte_wp_at_norm_eq')
  apply (subst cte_wp_at_norm_eq' [where P="\<lambda>cte. isFinal (cteCap cte) sl m" for sl m]) 
  apply (simp only: isFinal_cte_wp_def imp_conv_disj de_Morgan_conj)
  apply (wp hoare_vcg_ex_lift hoare_vcg_all_lift x hoare_vcg_disj_lift
            valid_cte_at_neg_typ' [OF y])
  done

lemma acap_relation_reset_mapping:
  "acap_relation acap acap' \<Longrightarrow> acap_relation (arch_reset_mem_mapping acap) (resetMemMapping acap')"
  by (cases acap, simp_all add: resetMemMapping_def)

crunch cteCaps_of: invalidateTLBByASID "\<lambda>s. P (cteCaps_of s)"

crunch valid_etcbs[wp]: invalidate_tlb_by_asid valid_etcbs

lemma cteCaps_of_ctes_of_lift:
  "(\<And>P. \<lbrace>\<lambda>s. P (ctes_of s)\<rbrace> f \<lbrace>\<lambda>_ s. P (ctes_of s)\<rbrace>) \<Longrightarrow> \<lbrace>\<lambda>s. P (cteCaps_of s) \<rbrace> f \<lbrace>\<lambda>_ s. P (cteCaps_of s)\<rbrace>"
  unfolding cteCaps_of_def .

lemma arch_recycle_cap_corres:
  notes arch_reset_mem_mapping.simps [simp del]
        static_imp_wp [wp]
  shows "\<lbrakk>acap_relation cap cap'; final_matters' (capability.ArchObjectCap cap') \<longrightarrow> is_final = is_final'\<rbrakk> \<Longrightarrow>
   corres acap_relation
     (invs and valid_etcbs and cte_wp_at (op = (cap.ArchObjectCap cap)) slot and
         valid_cap (cap.ArchObjectCap cap) and 
     (\<lambda>s. final_matters (cap.ArchObjectCap cap) \<longrightarrow> is_final = is_final_cap' (cap.ArchObjectCap cap) s))
     (invs' and valid_cap' (capability.ArchObjectCap cap') and 
      (\<lambda>s. final_matters' (capability.ArchObjectCap cap') \<longrightarrow>
           is_final' = isFinal (capability.ArchObjectCap cap') (cte_map slot) (cteCaps_of s)))
     (arch_recycle_cap is_final cap) (ArchRetypeDecls_H.recycleCap is_final' cap')"
  apply (simp add: arch_recycle_cap_def ArchRetype_H.recycleCap_def final_matters'_def split_def
                    split del: split_if)
  apply (cases cap, simp_all add: isCap_simps split del: split_if)
     -- "ASID pool"
     apply (simp add: makeObject_asidpool const_None_empty)
     apply (rule corres_guard_imp)
       apply (rule corres_split [OF _ corres_gets_asid])
         apply (rule corres_split_nor)
            apply (rule corres_trivial, simp)
           apply (rule corres_when)
            apply simp
           apply (rule corres_split_nor [OF _ delete_asid_pool_corres])
             apply (rule corres_split [OF _ set_asid_pool_corres])
                apply (rule corres_split [OF _ corres_gets_asid])
                  apply (rule corres_trivial, rule corres_modify)
                  apply (clarsimp simp: state_relation_def
                                        arch_state_relation_def fun_upd_def)
                  apply (rule ext)
                  apply (clarsimp simp: up_ucast_inj_eq)
                 apply (wp | simp add: inv_def)+
      apply (auto simp: valid_cap_def valid_cap'_def inv_def mask_def)[2]
    -- "PageCap"
    apply (rename_tac word vmrights vmpage_size option)
    apply (rule corres_guard_imp)
      apply (rule corres_split [where r' = dc])
         apply (rule corres_split [where R = "\<top>\<top>" and R' = "\<top>\<top>" and r' = cap_relation])
            apply (simp add: acap_relation_reset_mapping)
           apply (rule arch_finalise_cap_corres [where sl = slot])
            apply (simp add:final_matters'_def)
           apply simp
          apply wp
        apply (rule_tac F = "is_aligned word 2" in corres_gen_asm2)
        apply (rule corres_machine_op)
        apply (rule corres_guard_imp)
          apply (simp add: shiftL_nat)
          apply (rule clearMemory_corres)
         apply simp
        apply assumption
       apply simp
       apply (wp do_machine_op_valid_cap no_irq_clearMemory)
     apply simp
    apply simp
    apply (clarsimp simp add: valid_cap'_def capAligned_def final_matters'_def)
    apply (erule is_aligned_weaken)
    apply (case_tac vmpage_size, simp_all)[1]
   -- "PageTable"
   apply (rename_tac word option)
   apply (simp add: mapM_x_mapM objBits_simps archObjSize_def split del: split_if)
   apply (rule_tac F="is_aligned word pt_bits" in corres_req)
    apply (clarsimp simp: valid_cap_def cap_aligned_def
                          pt_bits_def pageBits_def)
   apply (simp add: upto_enum_step_subtract[where x=x and y="x + 4" for x]
                    is_aligned_no_overflow pt_bits_stuff
                    upto_enum_step_red[where us=2, simplified]
               split del: split_if)
   apply (rule corres_guard_imp)
     apply (rule corres_split_nor)
        apply (rule corres_split_nor)
           apply (rule corres_split_nor)
              apply (rule corres_split)
                 apply (rule corres_trivial,
                        clarsimp simp add: acap_relation_reset_mapping)
                apply (rule arch_finalise_cap_corres [where sl = slot])
                 apply simp
                apply simp
               apply wp
             apply (rename_tac opt_pd)
             apply (rule corres_option_split [OF refl])
              apply (rule corres_trivial, simp) 
             apply (simp add: split_def split del: split_if)
             apply (rule corres_split_eqr)
                apply (rule corres_when [OF refl])
                apply (rule_tac pd="the pdOpt" in invalidate_tlb_by_asid_corres)
               apply (rule page_table_mapped_corres)
              apply (wp page_table_mapped_wp)
             apply (rule hoare_drop_imps, wp)
            apply (simp add: case_prod_beta case_option_If2 split del: split_if)
            apply (wp  invalidate_tlb_by_asid_valid_cap final_cap_lift page_table_mapped_wp)
           apply (simp add: case_prod_beta case_option_If2 split del: split_if)
           apply (wp invalidateTLBByASID_cteCaps_of | simp)+
          apply (rule corres_machine_op)
          apply (rule corres_Id)
            apply simp
           apply simp
          apply (rule no_fail_cleanCacheRange_PoU)
         apply (simp add: case_option_If2 if_apply_def2 split del: split_if)
         apply (wp do_machine_op_valid_cap | wp_once hoare_drop_imps)+
        apply (simp add: case_option_If2 if_apply_def2 split del: split_if)
        apply (wp do_machine_op_valid_cap hoare_vcg_all_lift
                  no_irq_cleanCacheRange_PoU hoare_vcg_const_imp_lift)
       apply (rule_tac r'=dc and S="op ="
         and Q="\<lambda>xs s. \<forall>x \<in> set xs. pte_at x s \<and> pspace_aligned s \<and> valid_etcbs s"
         and Q'="\<lambda>xs s. \<forall>x \<in> set xs. pte_at' x s"
         in corres_mapM_list_all2, simp_all)[1]
          apply (rule corres_guard_imp)
            apply (rule store_pte_corres)
            apply (simp add:pte_relation_aligned_def)
         apply (wp hoare_vcg_const_Ball_lift store_pte_typ_at | simp)+
       apply (simp add: list_all2_refl)
      apply (rule hoare_strengthen_post)
       apply (rule_tac 
         Q'="\<lambda>rv. valid_etcbs and valid_cap (cap.ArchObjectCap cap) and (\<lambda>s. is_final = is_final_cap' (cap.ArchObjectCap cap) s \<and> cte_wp_at (op = (cap.ArchObjectCap cap)) slot s)" 
         in hoare_vcg_conj_lift)
        apply (rule mapM_swp_store_pte_invs)
       apply (wp mapM_wp' hoare_vcg_const_imp_lift | simp)+
      apply (clarsimp simp: valid_cap_def mask_def word_neq_0_conv)
      apply auto[1]
     apply simp
     apply (wp, rule mapM_wp')
      apply (wp cteCaps_of_ctes_of_lift mapM_storePTE_invs
                mapM_wp' cteCaps_of_ctes_of_lift hoare_vcg_all_lift
             | simp add: swp_def)+
    apply (clarsimp simp: invs_pspace_alignedI valid_cap_def)
    apply (intro conjI)
     apply (clarsimp simp: upto_enum_step_def)
     apply (erule page_table_pte_atI[simplified shiftl_t2n mult.commute mult.left_commute,simplified])
      apply (simp add: ptBits_def pageBits_def pt_bits_stuff)
      apply (simp add: word_less_nat_alt unat_of_nat)
     apply clarsimp
    apply (cases slot, clarsimp)
    apply (intro exI, erule cte_wp_at_weakenE)
    apply (clarsimp simp: is_cap_simps word32_shift_by_2 upto_enum_step_def)
    apply (rule conjunct2[OF is_aligned_add_helper[OF _ shiftl_less_t2n]],
           simp_all add: pt_bits_def pageBits_def ptBits_def)[1]
    apply (simp add: word_less_nat_alt unat_of_nat)
   apply clarsimp
   apply (clarsimp simp: valid_cap'_def page_table_at'_def shiftl_t2n mult.commute mult.left_commute)
   apply (rule conjI[rotated])
    apply auto[1]
   apply (clarsimp simp: upto_enum_step_def)
   apply (drule spec, erule mp)
   apply (simp add: ptBits_def pageBits_def)
   apply (simp add: word_less_nat_alt unat_of_nat)
  -- "PageDirectory"
  apply (rule corres_guard_imp)
    apply (rule corres_split)
       prefer 2
       apply (simp add: liftM_def[symmetric] o_def dc_def[symmetric]
                        mapM_x_mapM)
       apply (simp add: kernel_base_def kernelBase_def 
                        objBits_simps archObjSize_def)
       apply (rule corres_guard_imp)
         apply (rule_tac r'=dc and S="op ="
                     and Q="\<lambda>xs s. \<forall>x \<in> set xs. pde_at x s \<and> pspace_aligned s \<and> valid_etcbs s"
                     and Q'="\<lambda>xs s. \<forall>x \<in> set xs. pde_at' x s"
                      in corres_mapM_list_all2, simp_all)[1]
            apply (rule corres_guard_imp, rule store_pde_corres)
              apply (simp add:pde_relation_aligned_def)
             apply (wp hoare_vcg_const_Ball_lift | simp)+
         apply (simp add: list_all2_refl)
        apply assumption
       apply assumption
      apply (rule corres_split_nor)
         apply (rule corres_split_nor)
           -- "clag from above"
            apply (rule corres_split)
               apply (rule corres_trivial,
                      clarsimp simp add: acap_relation_reset_mapping)
              apply (rule arch_finalise_cap_corres [where sl = slot])
               apply simp
              apply simp 
             apply wp
           apply (rename_tac opt_pd)
           apply (rule corres_option_split [OF refl])
            apply (rule corres_trivial, simp) 
           apply (simp add: ignoreFailure_def split del: split_if)
           apply (rule corres_split_catch)
              apply (rule corres_trivial, simp)
             apply (rule corres_split_eqrE [OF _ find_pd_for_asid_corres])
               apply (simp add: dc_def[symmetric])
               apply (rule corres_when, fastforce)
               apply (rule_tac pd=rv in invalidate_tlb_by_asid_corres)
              apply (wp hoare_drop_imps)[2]
            apply (wp hoare_when_weak_wp invalidate_tlb_by_asid_invs
                      invalidate_tlb_by_asid_valid_cap final_cap_lift
                      invalidateTLBByASID_cteCaps_of hoare_vcg_const_imp_lift
                   | wpc | simp add: if_apply_def2 split del: split_if)+
        apply (rule corres_machine_op, rule corres_Id)
          apply (simp add: pd_bits_def pdBits_def)
         apply simp
        apply ((wp no_fail_cleanCacheRange_PoU no_irq_cleanCacheRange_PoU
                   do_machine_op_valid_cap do_machine_op_valid_arch
                   hoare_vcg_const_imp_lift hoare_vcg_all_lift hoare_vcg_disj_lift
                | simp add: case_option_If2 if_apply_def2
                       split del: split_if)+)[3]
     apply (rule hoare_strengthen_post)
      apply (rule_tac 
        Q'="\<lambda>rv. valid_etcbs and valid_cap (cap.ArchObjectCap cap) and
                 (\<lambda>s. is_final = is_final_cap' (cap.ArchObjectCap cap) s \<and>
                      cte_wp_at (op = (cap.ArchObjectCap cap)) slot s)"
        in hoare_vcg_conj_lift, rule mapM_x_swp_store_pde_invs_unmap)
      apply (wp mapM_x_wp' hoare_vcg_const_imp_lift final_cap_lift | simp)+
     apply (clarsimp simp: valid_cap_def mask_def asidBits_asid_bits)
     apply auto[1]
    apply (wp mapM_x_wp' valid_arch_state_lift' cteCaps_of_ctes_of_lift
              hoare_vcg_const_imp_lift hoare_vcg_all_lift | simp)+
   apply (clarsimp simp: invs_psp_aligned valid_cap_def field_simps
                         invs_arch_state pde_ref_def cap_aligned_def
                         pd_bits_14[symmetric] field_simps mask_add_aligned
                         arch_recycle_slots_kernel_mapping_slots)
   apply (intro conjI allI impI)
    apply (erule page_directory_pde_atI)
     apply (erule order_le_less_trans)
     apply (simp add: pageBits_def)
    apply clarsimp
   apply (subst is_aligned_add_helper[OF _ shiftl_less_t2n]; simp add: kernel_base_def pd_bits_14)
    apply (erule order_le_less_trans, simp)
   apply (clarsimp simp: cte_wp_at_caps_of_state)
   apply (drule valid_global_refsD2, clarsimp)
   apply (simp add: cap_range_def)
  apply (clarsimp simp: valid_cap'_def page_directory_at'_def 
                        field_simps invs_arch_state')
  apply (rule conjI)
   apply clarsimp
   apply (drule spec, erule mp)
   apply (erule order_le_less_trans, simp)
  apply auto[1]
  done

lemmas final_matters'_simps = final_matters'_def [split_simps capability.split arch_capability.split]

definition set_thread_all :: "obj_ref \<Rightarrow> Structures_A.tcb \<Rightarrow> etcb
                                \<Rightarrow> unit det_ext_monad" where
  "set_thread_all ptr tcb etcb \<equiv>
     do s \<leftarrow> get;
       kh \<leftarrow> return $ kheap s(ptr \<mapsto> (TCB tcb));
       ekh \<leftarrow> return $ (ekheap s)(ptr \<mapsto> etcb);
       put (s\<lparr>kheap := kh, ekheap := ekh\<rparr>)
     od"

definition thread_gets_the_all :: "obj_ref \<Rightarrow> (Structures_A.tcb \<times> etcb) det_ext_monad" where
  "thread_gets_the_all tptr \<equiv>
          do tcb \<leftarrow> gets_the $ get_tcb tptr;
             etcb \<leftarrow> gets_the $ get_etcb tptr;
             return $ (tcb, etcb) od"

definition thread_set_all :: "(Structures_A.tcb \<Rightarrow> Structures_A.tcb) \<Rightarrow> (etcb \<Rightarrow> etcb)
                  \<Rightarrow> obj_ref \<Rightarrow> unit det_ext_monad" where
  "thread_set_all f g tptr \<equiv>
     do (tcb, etcb) \<leftarrow> thread_gets_the_all tptr;
        set_thread_all tptr (f tcb) (g etcb)
     od"

lemma thread_set_ethread_set_all:
  "do thread_set f t; ethread_set g t od
   = thread_set_all f g t"
  by (rule ext) (clarsimp simp: thread_set_def ethread_set_def gets_the_def set_object_def set_object_def fail_def assert_opt_def split_def do_extended_op_def thread_set_all_def set_thread_all_def set_eobject_def thread_gets_the_all_def bind_def gets_def get_def return_def put_def get_etcb_def split: option.splits)

lemma set_thread_all_corres:
  fixes ob' :: "'a :: pspace_storable"
  assumes x: "updateObject ob' = updateObject_default ob'"
  assumes z: "\<And>s. obj_at' P ptr s
               \<Longrightarrow> map_to_ctes ((ksPSpace s) (ptr \<mapsto> injectKO ob')) = map_to_ctes (ksPSpace s)"
  assumes b: "\<And>ko. P ko \<Longrightarrow> objBits ko = objBits ob'"
  assumes P: "\<And>(v::'a::pspace_storable). (1 :: word32) < 2 ^ (objBits v)"
  assumes e: "etcb_relation etcb tcb'"
  assumes is_t: "injectKO (ob' :: 'a :: pspace_storable) = KOTCB tcb'"
  shows      "other_obj_relation (TCB tcb) (injectKO (ob' :: 'a :: pspace_storable)) \<Longrightarrow>
  corres dc (obj_at (same_caps (TCB tcb)) ptr and is_etcb_at ptr)
            (obj_at' (P :: 'a \<Rightarrow> bool) ptr)
            (set_thread_all ptr tcb etcb) (setObject ptr ob')"
  apply (rule corres_no_failI)
   apply (rule no_fail_pre)
    apply wp
    apply (rule x)
   apply (clarsimp simp: b elim!: obj_at'_weakenE)
  apply (unfold set_thread_all_def setObject_def)
  apply (clarsimp simp: in_monad split_def bind_def gets_def get_def Bex_def
                        put_def return_def modify_def get_object_def x
                        projectKOs
                        updateObject_default_def in_magnitude_check [OF _ P])
  apply (clarsimp simp add: state_relation_def z)
  apply (simp add: trans_state_update'[symmetric] trans_state_update[symmetric]
         del: trans_state_update)
  apply (clarsimp simp add: caps_of_state_after_update cte_wp_at_after_update
                            swp_def fun_upd_def obj_at_def is_etcb_at_def)
  apply (subst conj_assoc[symmetric])
  apply (rule conjI[rotated])
   apply (clarsimp simp add: ghost_relation_def)
   apply (erule_tac x=ptr in allE)+
   apply (clarsimp simp: obj_at_def a_type_def 
                   split: Structures_A.kernel_object.splits split_if_asm)
  apply (fold fun_upd_def)
  apply (simp only: pspace_relation_def dom_fun_upd2 simp_thms)
  apply (subst pspace_dom_update)
    apply assumption
   apply simp
  apply (simp only: dom_fun_upd2 simp_thms)
  apply (elim conjE)
  apply (frule bspec, erule domI)
  apply (rule conjI)
   apply (rule ballI, drule(1) bspec)
   apply (drule domD)
   apply (clarsimp simp: is_other_obj_relation_type)
   apply (drule(1) bspec)
   apply clarsimp
   apply (frule_tac ko'="TCB tcb'" and x'=ptr in obj_relation_cut_same_type,
           (fastforce simp add: is_other_obj_relation_type)+)[1]
  apply (simp only: ekheap_relation_def dom_fun_upd2 simp_thms)
  apply (frule bspec, erule domI)
  apply (rule ballI, drule(1) bspec)
  apply (drule domD)
  apply (clarsimp simp: obj_at'_def)
  apply (clarsimp simp: projectKOs)
  apply (insert e is_t)
  apply (clarsimp simp: a_type_def other_obj_relation_def etcb_relation_def is_other_obj_relation_type split: Structures_A.kernel_object.splits Structures_H.kernel_object.splits ARM_Structs_A.arch_kernel_obj.splits)
  done

lemma tcb_update_all_corres':
  assumes tcbs: "tcb_relation tcb tcb' \<Longrightarrow> tcb_relation tcbu tcbu'"
  assumes tables: "\<forall>(getF, v) \<in> ran tcb_cap_cases. getF tcbu = getF tcb"
  assumes tables': "\<forall>(getF, v) \<in> ran tcb_cte_cases. getF tcbu' = getF tcb'"
  assumes r: "r () ()"
  assumes e: "etcb_relation etcb tcb' \<Longrightarrow> etcb_relation etcbu tcbu'"
  shows "corres r (ko_at (TCB tcb) add and (\<lambda>s. ekheap s add = Some etcb))
                  (ko_at' tcb' add)
                  (set_thread_all add tcbu etcbu) (setObject add tcbu')"
  apply (rule_tac F="tcb_relation tcb tcb' \<and> etcb_relation etcbu tcbu'" in corres_req)
   apply (clarsimp simp: state_relation_def obj_at_def obj_at'_def)
   apply (frule(1) pspace_relation_absD)
   apply (force simp: projectKOs other_obj_relation_def ekheap_relation_def e)
  apply (erule conjE)
  apply (rule corres_guard_imp)
    apply (rule corres_rel_imp)
     apply (rule set_thread_all_corres[where P="op = tcb'"])
           apply (rule ext)+
           apply simp
          defer
          apply (simp add: is_other_obj_relation_type_def a_type_def
                           projectKOs objBits_simps
                           other_obj_relation_def tcbs r)+
    apply (fastforce simp: is_etcb_at_def elim!: obj_at_weakenE dest: bspec[OF tables])
   apply (subst(asm) eq_commute, assumption)
  apply (clarsimp simp: projectKOs obj_at'_def objBits_simps)
  apply (subst map_to_ctes_upd_tcb, assumption+)
   apply (simp add: ps_clear_def3 field_simps)
  apply (subst if_not_P)
   apply (fastforce dest: bspec [OF tables', OF ranI])
  apply simp
  done

lemma thread_gets_the_all_corres:
  shows      "corres (\<lambda>(tcb, etcb) tcb'. tcb_relation tcb tcb' \<and> etcb_relation etcb tcb')
                (tcb_at t and is_etcb_at t) (tcb_at' t)
                (thread_gets_the_all t) (getObject t)"
  apply (rule corres_no_failI)
   apply wp
  apply (clarsimp simp add: gets_def get_def return_def bind_def get_tcb_def thread_gets_the_all_def threadGet_def ethread_get_def gets_the_def assert_opt_def get_etcb_def is_etcb_at_def tcb_at_def liftM_def split: option.splits Structures_A.kernel_object.splits)
  apply (frule in_inv_by_hoareD [OF getObject_inv_tcb])
  apply (clarsimp simp add: obj_at_def is_tcb obj_at'_def projectKO_def 
                            projectKO_opt_tcb split_def
                            getObject_def loadObject_default_def in_monad)
  apply (case_tac ko)
   apply (simp_all add: fail_def return_def)
  apply (clarsimp simp add: state_relation_def pspace_relation_def ekheap_relation_def)
  apply (drule bspec)
   apply clarsimp
   apply blast
  apply (drule bspec, erule domI)
  apply (clarsimp simp add: other_obj_relation_def
                            lookupAround2_known1)
  done

lemma thread_set_all_corresT:
  assumes x: "\<And>tcb tcb'. tcb_relation tcb tcb' \<Longrightarrow>
                         tcb_relation (f tcb) (f' tcb')"
  assumes y: "\<And>tcb. \<forall>(getF, setF) \<in> ran tcb_cap_cases. getF (f tcb) = getF tcb"
  assumes z: "\<forall>tcb. \<forall>(getF, setF) \<in> ran tcb_cte_cases.
                 getF (f' tcb) = getF tcb"
  assumes e: "\<And>etcb tcb'. etcb_relation etcb tcb' \<Longrightarrow>
                         etcb_relation (g etcb) (f' tcb')"
  shows      "corres dc (tcb_at t and valid_etcbs) 
                        (tcb_at' t)
                    (thread_set_all f g t) (threadSet f' t)"
  apply (simp add: thread_set_all_def threadSet_def bind_assoc)
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ thread_gets_the_all_corres])
      apply (simp add: split_def)
      apply (rule tcb_update_all_corres')
          apply (erule x)
         apply (rule y)
        apply (clarsimp simp: bspec_split [OF spec [OF z]])
       apply fastforce
      apply (erule e)
     apply (simp add: thread_gets_the_all_def, wp)
   apply clarsimp
   apply (frule(1) tcb_at_is_etcb_at)
   apply (clarsimp simp add: tcb_at_def get_etcb_def obj_at_def)
   apply (drule get_tcb_SomeD)
   apply fastforce
  apply simp
  done

lemmas thread_set_all_corres =
    thread_set_all_corresT [OF _ _ all_tcbI, OF _ ball_tcb_cap_casesI ball_tcb_cte_casesI]

lemma thread_set_gets_futz:
  "thread_set F t >>= (\<lambda>_. gets cur_domain >>= g)
 = gets cur_domain >>= (\<lambda>cdom. thread_set F t >>= K (g cdom))"
apply (rule ext)
apply (simp add: assert_opt_def bind_def fail_def get_def gets_def gets_the_def put_def return_def set_object_def thread_set_def split_def
          split: option.splits)
done

lemma recycle_cap_corres:
  "\<lbrakk> cap_relation cap cap'; cap \<noteq> cap.NullCap;
     final_matters' cap' \<longrightarrow> is_final = is_final'\<rbrakk> \<Longrightarrow>
   corres cap_relation (invs and valid_sched and cte_wp_at (op = cap) slot and valid_cap cap and
                        (\<lambda>s. final_matters cap \<longrightarrow> is_final = is_final_cap' cap s))
                       (invs' and valid_cap' cap' and
                        (\<lambda>s. final_matters' cap' \<longrightarrow>
                             is_final' = isFinal cap' (cte_map slot) (cteCaps_of s)))
    (recycle_cap is_final cap) (recycleCap is_final' cap')"
  using [[ hypsubst_thin = true ]]
  apply (simp add: recycle_cap_def recycleCap_def split del: split_if)
  apply (cases cap, simp_all split del: split_if add: isCap_simps final_matters'_simps,
                    safe, simp_all)
      apply (simp add: liftM_def[symmetric] o_def dc_def[symmetric])
      apply (clarsimp simp add: when_def)
      apply (rule corres_guard_imp, rule ep_cancel_badged_sends_corres)
      apply (simp add: valid_cap_def)
     apply (simp add: valid_cap'_def)
    apply (rename_tac word option nat)
    apply (case_tac option; simp)
     apply (simp add: Let_def zbits_map_def allRights_def
                      get_thread_state_def)
     apply (rule stronger_corres_guard_imp)
       apply (rule corres_split)
          prefer 2
          apply (rule_tac r="\<lambda>st tcb. thread_state_relation st (tcbState tcb)"
                      in threadget_corres)
          apply (simp add: tcb_relation_def)
         apply (rule_tac F="inactive st" in corres_gen_asm)
         apply (rule_tac F="\<not> tcbQueued rv'" in corres_gen_asm2)
         apply (simp add: recycle_cap_ext_def bind_assoc thread_set_gets_futz)
         apply (rule corres_split[OF _ gcd_corres])
         apply (subst bind_cong[OF thread_set_ethread_set_all refl, simplified bind_assoc, simplified])
         apply (simp add: liftM_def[symmetric] o_def dc_def[symmetric])
         apply (rule thread_set_all_corres, simp_all add: tcb_registers_caps_merge_def)[1]
            apply (simp add: tcb_relation_def default_tcb_def makeObject_tcb
                             new_context_def newContext_def
                             fault_rel_optionation_def initContext_def)
           apply (simp add: etcb_relation_def default_etcb_def makeObject_tcb timeSlice_def
                            minBound_word default_priority_def time_slice_def)
          apply (wp gets_wp)
         apply (simp add: curDomain_def)
         apply (wp gets_wp)
        apply (simp add: get_thread_state_def[symmetric])
        apply (wp threadGet_const gts_st_tcb_at)
      apply (clarsimp simp: valid_cap_def st_tcb_def2 tcb_at_def)
      apply (frule zombie_not_ex_cap_to, clarsimp)
      apply (rule ccontr, erule notE, rule_tac P="op = v" for v in st_tcb_ex_cap)
        apply (simp add: st_tcb_def2)
       apply clarsimp
      apply (clarsimp simp: valid_sched_def split: Structures_A.thread_state.split_asm)
      apply (subgoal_tac "st_tcb_at idle word s")
       prefer 2
       apply (drule get_tcb_SomeD)
       apply (simp add: st_tcb_at_def obj_at_def)
      apply (drule only_idleD)
       apply (simp add: invs_def valid_state_def)
      apply (clarsimp simp: cte_wp_at_caps_of_state)
      apply (drule valid_global_refsD2, fastforce)
      apply (clarsimp simp: cap_range_def)
     apply (clarsimp simp: valid_cap'_def obj_at'_def projectKOs)
     apply (frule_tac p=word in if_live_then_nonz_capE'[OF invs_iflive'])
      apply (clarsimp simp: ko_wp_at'_def)
     apply (clarsimp simp: ex_nonz_cap_to'_def)
     apply (subst(asm) cte_wp_at_norm_eq', clarsimp)
     apply (drule pspace_relation_cte_wp_atI'[rotated])
       apply (erule invs_valid_objs)
      apply (clarsimp simp: state_relation_def)
     apply clarsimp
     apply (drule zombie_not_ex_cap_to, clarsimp)
     apply (erule notE, simp(no_asm) add: ex_nonz_cap_to_def)
     apply (intro exI, erule cte_wp_at_weakenE)
     apply (case_tac ca, auto)[1]
    apply (simp add: Let_def zbits_map_def allRights_def)
   apply (simp add: o_def)
   apply (rule corres_guard_imp [OF arch_recycle_cap_corres], auto simp: valid_sched_def)[1]
  apply (rule corres_guard_imp)
    apply (simp add: o_def)
    apply (rule arch_recycle_cap_corres)
     apply (force simp: valid_sched_def)+
  done

crunch typ_at'[wp]: recycleCap "\<lambda>s. P (typ_at' T p s)"
  (ignore: filterM 
     simp: crunch_simps filterM_mapM unless_def
           arch_recycleCap_improve_cases
       wp: crunch_wps)

lemmas recycleCap_typ_at_lifts[wp]
    = typ_at_lifts [OF recycleCap_typ_at']

lemma no_fail_getSlotCap:
  "no_fail (cte_at' p) (getSlotCap p)"
  apply (rule no_fail_pre)
  apply (simp add: getSlotCap_def | wp)+
  done

crunch idle_thread[wp]: deleteCallerCap "\<lambda>s. P (ksIdleThread s)"
crunch sch_act_simple: deleteCallerCap sch_act_simple
crunch sch_act_not[wp]: deleteCallerCap "sch_act_not t"
crunch typ_at'[wp]: deleteCallerCap "\<lambda>s. P (typ_at' T p s)"
lemmas deleteCallerCap_typ_ats[wp] = typ_at_lifts [OF deleteCallerCap_typ_at']

crunch ksQ[wp]: emptySlot "\<lambda>s. P (ksReadyQueues s p)"

lemma setEndpoint_sch_act_not_ct[wp]:
  "\<lbrace>\<lambda>s. sch_act_not (ksCurThread s) s\<rbrace>
   setEndpoint ptr val \<lbrace>\<lambda>_ s. sch_act_not (ksCurThread s) s\<rbrace>"
  by (rule hoare_weaken_pre, wps setEndpoint_ct', wp, simp)

lemma cancelAll_ct_not_ksQ_helper:
  "\<lbrace>(\<lambda>s. ksCurThread s \<notin> set (ksReadyQueues s p)) and (\<lambda>s. ksCurThread s \<notin> set q) \<rbrace>
   mapM_x (\<lambda>t. do
                 y \<leftarrow> setThreadState Structures_H.thread_state.Restart t;
                 tcbSchedEnqueue t
               od) q
   \<lbrace>\<lambda>rv s. ksCurThread s \<notin> set (ksReadyQueues s p)\<rbrace>"
  apply (rule mapM_x_inv_wp2, simp)
  apply (wp)
   apply (wps tcbSchedEnqueue_ct')
   apply (wp tcbSchedEnqueue_ksQ)
  apply (rule hoare_weaken_pre)
   apply (wps setThreadState_ct')
   apply (wp sts_ksQ')
  apply (clarsimp)
  done

lemma epCancelAll_ct_not_ksQ:
  "\<lbrace>invs' and ct_in_state' simple' and sch_act_sane
          and (\<lambda>s. ksCurThread s \<notin> set (ksReadyQueues s p))\<rbrace>
   epCancelAll epptr
   \<lbrace>\<lambda>rv s. ksCurThread s \<notin> set (ksReadyQueues s p)\<rbrace>"
  (is "\<lbrace>?PRE\<rbrace> _ \<lbrace>\<lambda>_. ?POST\<rbrace>")
  apply (simp add: epCancelAll_def)
  apply (wp, wpc, wp)
       apply (wps rescheduleRequired_ct')
       apply (wp rescheduleRequired_ksQ')
      apply (clarsimp simp: forM_x_def)
      apply (wp cancelAll_ct_not_ksQ_helper mapM_x_wp_inv)
     apply (wp hoare_lift_Pf2 [OF setEndpoint_ksQ setEndpoint_ct'])
     apply (wps rescheduleRequired_ct')
     apply (wp rescheduleRequired_ksQ')
    apply (clarsimp simp: forM_x_def)
    apply (wp cancelAll_ct_not_ksQ_helper mapM_x_wp_inv)
   apply (wp hoare_lift_Pf2 [OF setEndpoint_ksQ setEndpoint_ct'])
  apply (rule_tac Q="\<lambda>ep. ?PRE and ko_at' ep epptr" in hoare_post_imp)
   apply (clarsimp)
   apply (rule conjI)
    apply ((clarsimp simp: invs'_def valid_state'_def
                           sch_act_sane_def
            | drule(1) ct_not_in_epQueue)+)[2]
  apply (wp get_ep_sp')
  done

lemma aepCancelAll_ct_not_ksQ:
  "\<lbrace>invs' and ct_in_state' simple' and sch_act_sane
          and (\<lambda>s. ksCurThread s \<notin> set (ksReadyQueues s p))\<rbrace>
   aepCancelAll aepptr
   \<lbrace>\<lambda>rv s. ksCurThread s \<notin> set (ksReadyQueues s p)\<rbrace>"
  (is "\<lbrace>?PRE\<rbrace> _ \<lbrace>\<lambda>_. ?POST\<rbrace>")
  apply (simp add: aepCancelAll_def)
  apply (wp, wpc, wp)
     apply (wps rescheduleRequired_ct')
     apply (wp rescheduleRequired_ksQ')
    apply (clarsimp simp: forM_x_def)
    apply (wp cancelAll_ct_not_ksQ_helper mapM_x_wp_inv)
   apply (wp hoare_lift_Pf2 [OF setAsyncEP_ksQ setAsyncEP_ct'])
   apply (wps setAsyncEP_ct', wp)
  apply (rule_tac Q="\<lambda>ep. ?PRE and ko_at' ep aepptr" in hoare_post_imp)
   apply ((clarsimp simp: invs'_def valid_state'_def sch_act_sane_def
          | drule(1) ct_not_in_aepQueue)+)[1]
  apply (wp get_aep_sp')
  done

lemma finaliseCapTrue_standin_ct_not_ksQ:
  "\<lbrace>invs' and ct_in_state' simple' and sch_act_sane
          and (\<lambda>s. ksCurThread s \<notin> set (ksReadyQueues s p))\<rbrace>
   finaliseCapTrue_standin cap final
   \<lbrace>\<lambda>rv s. ksCurThread s \<notin> set (ksReadyQueues s p)\<rbrace>"
  apply (simp add: finaliseCapTrue_standin_def)
  apply (safe)
      apply (wp epCancelAll_ct_not_ksQ
                aepCancelAll_ct_not_ksQ, fastforce)+
  done

lemma cteDeleteOne_ct_not_ksQ:
  "\<lbrace>invs' and ct_in_state' simple' and sch_act_sane
          and (\<lambda>s. ksCurThread s \<notin> set (ksReadyQueues s p))\<rbrace>
   cteDeleteOne slot
   \<lbrace>\<lambda>rv s. ksCurThread s \<notin> set (ksReadyQueues s p)\<rbrace>"
  apply (simp add: cteDeleteOne_def unless_def split_def)
  apply (rule hoare_seq_ext [OF _ getCTE_sp])
  apply (case_tac "\<forall>final. finaliseCap (cteCap cte) final True = fail")
   apply (simp add: finaliseCapTrue_standin_simple_def)
   apply wp
   apply (clarsimp)
  apply (wp emptySlot_cteCaps_of hoare_lift_Pf2 [OF emptySlot_ksQ emptySlot_ct])
    apply (simp add: cteCaps_of_def)
    apply (wp_once hoare_drop_imps)
    apply (wp finaliseCapTrue_standin_ct_not_ksQ isFinalCapability_inv)
  apply (clarsimp)
  done

end
