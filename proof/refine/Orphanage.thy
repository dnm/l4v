(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory Orphanage
imports Refine
begin

definition
   is_active_thread_state :: "thread_state \<Rightarrow> bool"
where
   "is_active_thread_state ts \<equiv>
       isRunning ts \<or> isRestart ts"

definition
   is_active_tcb_ptr :: "machine_word \<Rightarrow> kernel_state \<Rightarrow> bool"
where
   "is_active_tcb_ptr tcb_ptr s \<equiv>
       st_tcb_at' is_active_thread_state tcb_ptr s"

lemma is_active_tcb_ptr_runnable':
  "is_active_tcb_ptr t s = st_tcb_at' runnable' t s"
  by (auto simp: is_active_tcb_ptr_def st_tcb_at'_def obj_at'_def
                 is_active_thread_state_def isRunning_def isRestart_def
          split: Structures_H.thread_state.split_asm)

definition
   all_active_tcb_ptrs :: "kernel_state \<Rightarrow> machine_word set"
where
   "all_active_tcb_ptrs s \<equiv>
       { tcb_ptr. is_active_tcb_ptr tcb_ptr s }"

definition
   all_queued_tcb_ptrs :: "kernel_state \<Rightarrow> machine_word set"
where
   "all_queued_tcb_ptrs s \<equiv>
       { tcb_ptr. \<exists> priority. tcb_ptr : set ((ksReadyQueues s) priority) }"

lemma st_tcb_at_neg':
  "(st_tcb_at' (\<lambda> ts. \<not> P ts) t s) = (tcb_at' t s \<and> \<not> st_tcb_at' P t s)"
  by (auto simp: st_tcb_at'_def obj_at'_def)

lemma st_tcb_at_neg2:
  "(\<not> st_tcb_at' P t s) = (st_tcb_at' (\<lambda> ts. \<not> P ts) t s \<or> \<not> tcb_at' t s)" 
  by (auto simp: st_tcb_at'_def obj_at'_def)

lemma st_tcb_at_double_neg':
  "(st_tcb_at' (\<lambda> ts. \<not> P ts \<and> \<not> Q ts) t s) =
   ((st_tcb_at' (\<lambda> ts. \<not> P ts) t s) \<and> (st_tcb_at' (\<lambda> ts. \<not> Q ts) t s))"
  apply (auto simp: st_tcb_at'_def obj_at'_def)
  done

definition
   no_orphans :: " kernel_state \<Rightarrow> bool"
where
  "no_orphans s \<equiv> 
      \<forall> tcb_ptr.
         (tcb_ptr : all_active_tcb_ptrs s
         \<longrightarrow>
         tcb_ptr = ksCurThread s \<or> tcb_ptr : all_queued_tcb_ptrs s \<or>
         ksSchedulerAction s = SwitchToThread tcb_ptr)"

lemma no_orphans_disj:
   "no_orphans = (\<lambda> s. 
           \<forall> tcb_ptr. tcb_ptr = ksCurThread s \<or>
                      tcb_ptr : all_queued_tcb_ptrs s \<or>
                      \<not> typ_at' TCBT tcb_ptr s \<or>
                      st_tcb_at' (\<lambda> state. \<not> is_active_thread_state state) tcb_ptr s \<or>
                      ksSchedulerAction s = SwitchToThread tcb_ptr)"
  apply clarsimp
  apply (rule ext)
  apply (unfold no_orphans_def all_active_tcb_ptrs_def
                is_active_tcb_ptr_def st_tcb_at_neg' typ_at_tcb')
  apply (auto intro: st_tcb_at_tcb_at')
  done

lemma no_orphans_lift:
   assumes typ_at'_is_lifted:
     "\<And> tcb_ptr. \<lbrace> \<lambda>s. \<not> typ_at' TCBT tcb_ptr s\<rbrace> f \<lbrace> \<lambda>_ s. \<not> typ_at' TCBT tcb_ptr s \<rbrace>"
   assumes ksCurThread_is_lifted:
     "\<And> tcb_ptr. \<lbrace> \<lambda>s. tcb_ptr = ksCurThread s \<rbrace> f \<lbrace> \<lambda>_ s. tcb_ptr = ksCurThread s \<rbrace>"
   assumes st_tcb_at'_is_lifted:
     "\<And>P p. \<lbrace> \<lambda>s. st_tcb_at' P p s\<rbrace> f \<lbrace> \<lambda>_ s. st_tcb_at' P p s \<rbrace>"
   assumes ksReadyQueues_is_lifted:
     "\<And>P. \<lbrace> \<lambda>s. P (ksReadyQueues s)\<rbrace> f \<lbrace> \<lambda>_ s. P (ksReadyQueues s) \<rbrace>"
   assumes ksSchedulerAction_is_lifted:
     "\<And>P. \<lbrace> \<lambda>s. P (ksSchedulerAction s)\<rbrace> f \<lbrace> \<lambda>_ s. P (ksSchedulerAction s) \<rbrace>"
   shows
     "\<lbrace> \<lambda>s. no_orphans s \<rbrace> f \<lbrace> \<lambda>_ s. no_orphans s \<rbrace>"
  apply (unfold no_orphans_disj
                all_active_tcb_ptrs_def
                all_queued_tcb_ptrs_def)
  apply (wp hoare_vcg_all_lift
            hoare_vcg_disj_lift)
   apply (rule ksCurThread_is_lifted)
  apply (wp hoare_vcg_disj_lift)
   apply (rule ksReadyQueues_is_lifted)
  apply (wp hoare_vcg_disj_lift)
   apply (rule typ_at'_is_lifted)
  apply (wp hoare_vcg_disj_lift)
   apply (rule st_tcb_at'_is_lifted)
  apply (rule ksSchedulerAction_is_lifted)
  done

lemma st_tcb_at'_is_active_tcb_ptr_lift:
  assumes "\<And>P P' t. \<lbrace>\<lambda>s. P (st_tcb_at' P' t s)\<rbrace> f \<lbrace>\<lambda>rv s. P (st_tcb_at' P' t s)\<rbrace>"
  shows "\<lbrace>\<lambda>s. P (is_active_tcb_ptr t s)\<rbrace> f \<lbrace>\<lambda>_ s. P (is_active_tcb_ptr t s)\<rbrace>"
  by (clarsimp simp: is_active_tcb_ptr_def) (rule assms)

lemma st_tcb_at'_all_active_tcb_ptrs_lift:
  assumes "\<And>P P' t. \<lbrace>\<lambda>s. P (st_tcb_at' P' t s)\<rbrace> f \<lbrace>\<lambda>rv s. P (st_tcb_at' P' t s)\<rbrace>"
  shows "\<lbrace>\<lambda>s. P (t \<in> all_active_tcb_ptrs s)\<rbrace> f \<lbrace>\<lambda>_ s. P (t \<in> all_active_tcb_ptrs s)\<rbrace>"
  by (clarsimp simp: all_active_tcb_ptrs_def)
     (rule st_tcb_at'_is_active_tcb_ptr_lift [OF assms])

lemma ksQ_all_queued_tcb_ptrs_lift:
  assumes "\<And>P p. \<lbrace>\<lambda>s. P (ksReadyQueues s p)\<rbrace> f \<lbrace>\<lambda>rv s. P (ksReadyQueues s p)\<rbrace>"
  shows "\<lbrace>\<lambda>s. P (t \<in> all_queued_tcb_ptrs s)\<rbrace> f \<lbrace>\<lambda>_ s. P (t \<in> all_queued_tcb_ptrs s)\<rbrace>"
  apply (clarsimp simp: all_queued_tcb_ptrs_def)
  apply (rule_tac P=P in P_bool_lift)
   apply (wp hoare_ex_wp assms)
  apply (clarsimp)
  apply (wp hoare_vcg_all_lift assms)
  done

definition
   almost_no_orphans :: "word32 \<Rightarrow> kernel_state \<Rightarrow> bool"
where
  "almost_no_orphans tcb_ptr s \<equiv> 
      \<forall> ptr. ptr = tcb_ptr \<or>
         (ptr : all_active_tcb_ptrs s
         \<longrightarrow>
         ptr = ksCurThread s \<or> ptr : all_queued_tcb_ptrs s \<or> 
         ksSchedulerAction s = SwitchToThread ptr)"

lemma no_orphans_strg_almost:
   "no_orphans s \<longrightarrow> almost_no_orphans tcb_ptr s"
  unfolding no_orphans_def almost_no_orphans_def
  apply simp
  done

lemma almost_no_orphans_disj:
   "almost_no_orphans tcb_ptr = (\<lambda> s. 
           \<forall> ptr. ptr = ksCurThread s \<or>
                  ptr : all_queued_tcb_ptrs s \<or>
                  \<not> typ_at' TCBT ptr s \<or>
                  st_tcb_at' (\<lambda> thread_state. \<not> is_active_thread_state thread_state) ptr s \<or>
                  ptr = tcb_ptr \<or>
                  ksSchedulerAction s = SwitchToThread ptr)"
  apply clarsimp
  apply (rule ext)
  apply (unfold almost_no_orphans_def all_active_tcb_ptrs_def
                is_active_tcb_ptr_def st_tcb_at_neg' typ_at_tcb')
  apply (auto intro: st_tcb_at_tcb_at')
  done

(****************************************************************************************************)

lemma invs_valid_queues':
  "invs' s \<longrightarrow> valid_queues' s" 
  by (clarsimp simp:invs'_def valid_state'_def)

declare invs_valid_queues'[rule_format, elim!]

crunch ksCurThread [wp]: setVMRoot "\<lambda> s. P (ksCurThread s)"
(wp: crunch_wps simp: crunch_simps)

crunch ksReadyQueues [wp]: asUser "\<lambda>s. P (ksReadyQueues s)"
(wp: crunch_wps simp: crunch_simps)

crunch no_orphans [wp]: getCurThread "no_orphans"

crunch no_orphans [wp]: threadGet "no_orphans"

crunch no_orphans [wp]: getAsyncEP "no_orphans"

lemma setCTE_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   setCTE p cte
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (rule no_orphans_lift)
  apply (wp setCTE_typ_at' setCTE_st_tcb_at')
  done

lemma setCTE_almost_no_orphans [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<rbrace>
   setCTE p cte
   \<lbrace> \<lambda>rv s. almost_no_orphans tcb_ptr s \<rbrace>"
  unfolding almost_no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift setCTE_typ_at' setCTE_st_tcb_at')
  done

crunch no_orphans [wp]: activateIdleThread "no_orphans"

lemma asUser_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   asUser thread f
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

lemma threadSet_no_orphans:
  "\<forall>tcb. \<not> is_active_thread_state (tcbState tcb) \<longrightarrow> \<not> is_active_thread_state (tcbState (F tcb)) \<Longrightarrow>
   \<lbrace> \<lambda>s. no_orphans s \<rbrace> 
   threadSet F tptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift threadSet_st_tcb_at2 | clarsimp)+
  done

lemma threadSet_almost_no_orphans:
  "\<forall>tcb. \<not> is_active_thread_state (tcbState tcb) \<longrightarrow> \<not> is_active_thread_state (tcbState (F tcb)) \<Longrightarrow>
   \<lbrace> \<lambda>s. almost_no_orphans ptr s \<rbrace> 
   threadSet F tptr
   \<lbrace> \<lambda>rv s. almost_no_orphans ptr s \<rbrace>"
  unfolding almost_no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift threadSet_st_tcb_at2 | clarsimp)+
  done

lemma all_active_tcb_ptrs_queue [simp]:
  "all_active_tcb_ptrs (ksReadyQueues_update f s) = all_active_tcb_ptrs s"
  by (clarsimp simp: all_active_tcb_ptrs_def is_active_tcb_ptr_def)

lemma setQueue_no_orphans_enq:
  "\<lbrace> \<lambda>s. no_orphans s \<and> set (ksReadyQueues s (d, prio)) \<subseteq> set qs \<rbrace>
   setQueue d prio qs
   \<lbrace> \<lambda>_ s. no_orphans s \<rbrace>"
  unfolding setQueue_def
  apply wp
  apply (clarsimp simp: no_orphans_def all_queued_tcb_ptrs_def
                  split: split_if_asm)
  apply fastforce
  done

lemma setQueue_almost_no_orphans_enq:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<and> set (ksReadyQueues s (d, prio)) \<subseteq> set qs \<and> tcb_ptr \<in> set qs \<rbrace> 
   setQueue d prio qs
   \<lbrace> \<lambda>_ s. no_orphans s \<rbrace>"
  unfolding setQueue_def
  apply wp
  apply (clarsimp simp: no_orphans_def almost_no_orphans_def all_queued_tcb_ptrs_def
                  split: split_if_asm)
  apply fastforce
  done

lemma setQueue_almost_no_orphans_enq_lift:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<and> set (ksReadyQueues s (d, prio)) \<subseteq> set qs \<rbrace> 
   setQueue d prio qs
   \<lbrace> \<lambda>_ s. almost_no_orphans tcb_ptr s \<rbrace>"
  unfolding setQueue_def
  apply wp
  apply (clarsimp simp: almost_no_orphans_def all_queued_tcb_ptrs_def
                  split: split_if_asm)
  apply fastforce
  done

lemma tcbSchedEnqueue_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   tcbSchedEnqueue tcb_ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding tcbSchedEnqueue_def
  apply (wp setQueue_no_orphans_enq threadSet_no_orphans | clarsimp simp: unless_def)+
   apply (wp getObject_tcb_wp | clarsimp simp: threadGet_def)+
  apply (drule obj_at_ko_at')
  apply auto
  done

lemma ko_at_obj_at':
  "ko_at' ko p s \<and> P ko \<Longrightarrow> obj_at' P p s"
  unfolding  obj_at'_def
  apply clarsimp
  done

lemma queued_in_queue:
  "\<lbrakk>valid_queues' s; ko_at' tcb tcb_ptr s; tcbQueued tcb\<rbrakk> \<Longrightarrow>
   \<exists> p. tcb_ptr \<in> set (ksReadyQueues s p)"
  unfolding valid_queues'_def
   apply (drule_tac x="tcbDomain tcb" in spec)
   apply (drule_tac x="tcbPriority tcb" in spec)
   apply (drule_tac x="tcb_ptr" in spec)
   apply (drule mp)
    apply (rule ko_at_obj_at')
    apply (auto simp: inQ_def)
  done

lemma tcbSchedEnqueue_almost_no_orphans:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<and> valid_queues' s \<rbrace>
   tcbSchedEnqueue tcb_ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding tcbSchedEnqueue_def
  apply (wp setQueue_almost_no_orphans_enq[where tcb_ptr=tcb_ptr] threadSet_no_orphans 
            | clarsimp simp: unless_def)+ 
   apply (wp getObject_tcb_wp | clarsimp simp: threadGet_def)+
  apply (drule obj_at_ko_at')
  apply clarsimp
  apply (rule_tac x=ko in exI)
  apply clarsimp
  apply (rule conjI)
   apply fastforce
  apply (unfold no_orphans_def almost_no_orphans_def)
  apply clarsimp
  apply (drule queued_in_queue)
    apply (fastforce simp: all_queued_tcb_ptrs_def)+
  done

lemma tcbSchedEnqueue_almost_no_orphans_lift:
  "\<lbrace> \<lambda>s. almost_no_orphans ptr s \<rbrace>
   tcbSchedEnqueue tcb_ptr
   \<lbrace> \<lambda>rv s. almost_no_orphans ptr s \<rbrace>"
  unfolding tcbSchedEnqueue_def
  apply (wp setQueue_almost_no_orphans_enq_lift threadSet_almost_no_orphans | clarsimp simp: unless_def)+
   apply (wp getObject_tcb_wp | clarsimp simp: threadGet_def)+
  apply (drule obj_at_ko_at')
  apply auto
  done

lemma ssa_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<and>
     (\<forall>t. sch_act_not t s \<or> t : all_queued_tcb_ptrs s \<or> ksCurThread s = t) \<rbrace>
   setSchedulerAction sa
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setSchedulerAction_def no_orphans_disj all_queued_tcb_ptrs_def 
  apply wp
  apply auto
  done

lemma ssa_almost_no_orphans:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<and>
     (\<forall>t. sch_act_not t s \<or> t : all_queued_tcb_ptrs s \<or> ksCurThread s = t) \<rbrace>
   setSchedulerAction (SwitchToThread tcb_ptr)
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setSchedulerAction_def no_orphans_disj almost_no_orphans_disj all_queued_tcb_ptrs_def 
  apply wp
  apply auto
  done

lemma ssa_almost_no_orphans_lift [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<and>
     (\<forall>t. sch_act_not t s \<or> t : all_queued_tcb_ptrs s \<or> ksCurThread s = t) \<rbrace>
   setSchedulerAction sa
   \<lbrace> \<lambda>rv s. almost_no_orphans tcb_ptr s \<rbrace>"
  unfolding setSchedulerAction_def almost_no_orphans_disj all_queued_tcb_ptrs_def 
  apply wp
  apply auto
  done

lemma tcbSchedEnqueue_inQueue [wp]:
  "\<lbrace> \<lambda>s. valid_queues' s \<rbrace>
   tcbSchedEnqueue tcb_ptr
   \<lbrace> \<lambda>rv s. tcb_ptr \<in> all_queued_tcb_ptrs s \<rbrace>"
  unfolding tcbSchedEnqueue_def all_queued_tcb_ptrs_def
  apply (wp | clarsimp simp: unless_def)+
   apply (rule_tac Q="\<lambda>rv. \<top>" in hoare_post_imp)
    apply fastforce
   apply (wp getObject_tcb_wp | clarsimp simp: threadGet_def)+
  apply (fastforce simp: obj_at'_def valid_queues'_def inQ_def)
  done

lemma rescheduleRequired_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<rbrace>
   rescheduleRequired
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding rescheduleRequired_def
  apply (wp tcbSchedEnqueue_no_orphans hoare_vcg_all_lift ssa_no_orphans | wpc | clarsimp)+
   apply (wps tcbSchedEnqueue_nosch, wp static_imp_wp)
   apply (rename_tac word t p)
   apply (rule_tac P="word = t" in hoare_gen_asm)
   apply (wp hoare_disjI1 | clarsimp)+
  done

lemma rescheduleRequired_almost_no_orphans [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<and> valid_queues' s \<rbrace>
   rescheduleRequired
   \<lbrace> \<lambda>rv s. almost_no_orphans tcb_ptr s \<rbrace>"
  unfolding rescheduleRequired_def
  apply (wp tcbSchedEnqueue_almost_no_orphans_lift hoare_vcg_all_lift | wpc | clarsimp)+
   apply (wps tcbSchedEnqueue_nosch, wp static_imp_wp)
   apply (rename_tac word t p)
   apply (rule_tac P="word = t" in hoare_gen_asm)
   apply (wp hoare_disjI1 | clarsimp)+
  done

lemma setThreadState_current_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<and> ksCurThread s = tcb_ptr \<and> valid_queues' s \<rbrace>
   setThreadState state tcb_ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setThreadState_def
  apply (wp | clarsimp)+
  apply (rule_tac Q="\<lambda>rv s. valid_queues' s \<and> no_orphans s" in hoare_post_imp)
   apply clarsimp
  apply (wp threadSet_valid_queues')
   apply (unfold no_orphans_disj all_queued_tcb_ptrs_def)
   apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift threadSet_st_tcb_at_state)
   apply (auto simp: inQ_def)
  done

lemma setThreadState_isRestart_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<and> st_tcb_at' isRestart tcb_ptr s \<and> valid_queues' s\<rbrace>
   setThreadState state tcb_ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setThreadState_def
  apply (wp | clarsimp)+
  apply (rule_tac Q="\<lambda>rv s. valid_queues' s \<and> no_orphans s" in hoare_post_imp)
   apply clarsimp
  apply (wp threadSet_valid_queues')
   apply (unfold no_orphans_disj all_queued_tcb_ptrs_def is_active_thread_state_def)
   apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift threadSet_st_tcb_at_state)
   apply (auto simp: st_tcb_at_double_neg' st_tcb_at_neg' inQ_def)
  done

lemma setThreadState_almost_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s\<rbrace>
   setThreadState state tcb_ptr
   \<lbrace> \<lambda>rv s. almost_no_orphans tcb_ptr s \<rbrace>"
  unfolding setThreadState_def
  apply (wp | clarsimp)+
  apply (rule_tac Q="\<lambda>rv s. valid_queues' s \<and> almost_no_orphans tcb_ptr s" in hoare_post_imp)
   apply clarsimp
  apply (wp threadSet_valid_queues')
   apply (unfold no_orphans_disj almost_no_orphans_disj all_queued_tcb_ptrs_def)
   apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift threadSet_st_tcb_at_state)
   apply (auto simp: inQ_def)
  done

lemma setThreadState_not_active_no_orphans:
  "\<not> is_active_thread_state state \<Longrightarrow>
   \<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<rbrace>
   setThreadState state tcb_ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setThreadState_def
  apply (wp | clarsimp)+
  apply (rule_tac Q="\<lambda>rv s. valid_queues' s \<and> no_orphans s" in hoare_post_imp)
   apply clarsimp
  apply (wp threadSet_valid_queues')
   apply (unfold no_orphans_disj all_queued_tcb_ptrs_def is_active_thread_state_def)
   apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift threadSet_st_tcb_at_state)
   apply (auto simp: isRunning_def isRestart_def inQ_def)
  done

lemma setThreadState_not_active_almost_no_orphans:
  "\<not> is_active_thread_state state \<Longrightarrow>
   \<lbrace> \<lambda>s. almost_no_orphans thread s \<and> valid_queues' s \<rbrace>
   setThreadState state tcb_ptr
   \<lbrace> \<lambda>rv s. almost_no_orphans thread s \<rbrace>"
  unfolding setThreadState_def
  apply (wp | clarsimp)+
  apply (rule_tac Q="\<lambda>rv s. valid_queues' s \<and> almost_no_orphans thread s" in hoare_post_imp)
   apply clarsimp
  apply (wp threadSet_valid_queues')
   apply (unfold almost_no_orphans_disj all_queued_tcb_ptrs_def is_active_thread_state_def)
   apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift threadSet_st_tcb_at_state)
   apply (auto simp: isRunning_def isRestart_def inQ_def)
  done

lemma activateThread_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> ct_in_state' activatable' s \<and> invs' s \<rbrace>
   activateThread
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding activateThread_def
  apply (wp gts_wp' setThreadState_isRestart_no_orphans | wpc | clarsimp)+
  apply (auto simp: ct_in_state'_def st_tcb_at'_def obj_at'_def isRestart_def)
  done

lemma setQueue_no_orphans_deq:
  "\<lbrace> \<lambda>s. \<exists> tcb_ptr. no_orphans s \<and> \<not> is_active_tcb_ptr tcb_ptr s \<and>
        queue = [x\<leftarrow>((ksReadyQueues s) (d, priority)). x \<noteq> tcb_ptr] \<rbrace>
   setQueue d priority queue
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setQueue_def
  apply (wp | clarsimp)+
  apply (fastforce simp: no_orphans_def all_queued_tcb_ptrs_def
                        all_active_tcb_ptrs_def is_active_tcb_ptr_def)
  done

lemma setQueue_almost_no_orphans_deq [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<and>
        queue = [x\<leftarrow>((ksReadyQueues s) (d, priority)). x \<noteq> tcb_ptr] \<rbrace>
   setQueue d priority queue
   \<lbrace> \<lambda>rv s. almost_no_orphans tcb_ptr s \<rbrace>"
  unfolding setQueue_def
  apply (wp | clarsimp)+
  apply (fastforce simp: almost_no_orphans_def all_queued_tcb_ptrs_def
                        all_active_tcb_ptrs_def is_active_tcb_ptr_def)
  done

lemma tcbSchedDequeue_almost_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   tcbSchedDequeue thread
   \<lbrace> \<lambda>rv s. almost_no_orphans thread s \<rbrace>"
  unfolding tcbSchedDequeue_def
  apply (wp threadSet_almost_no_orphans | simp cong: if_cong)+
  apply (simp add:no_orphans_strg_almost cong: if_cong)
  done

lemma tcbSchedDequeue_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> \<not> is_active_tcb_ptr tcb_ptr s \<rbrace>
   tcbSchedDequeue tcb_ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding tcbSchedDequeue_def
  apply (wp setQueue_no_orphans_deq threadSet_no_orphans | clarsimp)+
   apply (wp getObject_tcb_wp | clarsimp simp: threadGet_def)+
  apply (drule obj_at_ko_at')
  apply auto
  done

lemma switchToIdleThread_no_orphans' [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and>
          (is_active_tcb_ptr (ksCurThread s) s
             \<longrightarrow> ksCurThread s \<in> all_queued_tcb_ptrs s) \<rbrace>
   switchToIdleThread
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding switchToIdleThread_def setCurThread_def ArchThread_H.switchToIdleThread_def
  apply (simp add: no_orphans_disj all_queued_tcb_ptrs_def)
  apply (wp hoare_vcg_all_lift hoare_vcg_imp_lift hoare_vcg_disj_lift storeWordUser_typ'
       | clarsimp)+
  apply (auto simp: no_orphans_disj all_queued_tcb_ptrs_def is_active_tcb_ptr_def
                    st_tcb_at_neg' tcb_at_typ_at')
  done

lemma ct_in_state_ksSched [simp]:
  "ct_in_state' activatable' (ksSchedulerAction_update f s) = ct_in_state' activatable' s"
  unfolding ct_in_state'_def
  apply auto
  done

lemma no_orphans_ksIdle [simp]:
   "no_orphans (ksIdleThread_update f s) = no_orphans s"
  unfolding no_orphans_def all_active_tcb_ptrs_def all_queued_tcb_ptrs_def is_active_tcb_ptr_def
  apply auto
  done

crunch no_orphans [wp]: "ArchThreadDecls_H.switchToThread" "no_orphans"
(wp: no_orphans_lift ignore: MachineOps.clearExMonitor)

crunch ksCurThread [wp]: "ArchThreadDecls_H.switchToThread" "\<lambda> s. P (ksCurThread s)"
  (ignore: MachineOps.clearExMonitor)

crunch ksIdleThread [wp]: "ArchThreadDecls_H.switchToThread" "\<lambda> s. P (ksIdleThread s)"
  (ignore: MachineOps.clearExMonitor)

lemma ArchThreadDecls_H_switchToThread_all_queued_tcb_ptrs [wp]:
  "\<lbrace> \<lambda>s. P (all_queued_tcb_ptrs s) \<rbrace>
   ArchThreadDecls_H.switchToThread tcb_ptr
   \<lbrace> \<lambda>rv s. P (all_queued_tcb_ptrs s) \<rbrace>"
  unfolding ArchThread_H.switchToThread_def all_queued_tcb_ptrs_def
  apply (wp | clarsimp)+
  done

crunch ksSchedulerAction [wp]: "ArchThreadDecls_H.switchToThread" "\<lambda>s. P (ksSchedulerAction s)"
  (ignore: MachineOps.clearExMonitor)

lemma setCurThread_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and>
         (is_active_tcb_ptr (ksCurThread s) s \<longrightarrow> ksCurThread s : all_queued_tcb_ptrs s) \<rbrace>
   setCurThread newThread
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setCurThread_def
  apply (wp | clarsimp)+
  apply (unfold no_orphans_def all_queued_tcb_ptrs_def
                all_active_tcb_ptrs_def is_active_tcb_ptr_def)
  apply auto
  done

lemma tcbSchedDequeue_all_queued_tcb_ptrs:
  "\<lbrace>\<lambda>s. x \<in> all_queued_tcb_ptrs s \<and> x \<noteq> t \<rbrace>
   tcbSchedDequeue t \<lbrace>\<lambda>_ s. x \<in> all_queued_tcb_ptrs s\<rbrace>"
  apply (rule_tac Q="(\<lambda>s. x \<in> all_queued_tcb_ptrs s) and K (x \<noteq> t)"
           in hoare_pre_imp, clarsimp)
  apply (rule hoare_gen_asm)
  apply (clarsimp simp: tcbSchedDequeue_def all_queued_tcb_ptrs_def)
  apply (wp hoare_ex_wp)
  apply (rule_tac Q="\<lambda>_ s. x \<in> set (ksReadyQueues s (a, b))"
           in hoare_post_imp, clarsimp)
  apply (wp hoare_vcg_all_lift | simp)+
  done

lemma tcbSchedDequeue_all_active_tcb_ptrs[wp]:
  "\<lbrace>\<lambda>s. P (t' \<in> all_active_tcb_ptrs s)\<rbrace> tcbSchedDequeue t \<lbrace>\<lambda>_ s. P (t' \<in> all_active_tcb_ptrs s)\<rbrace>"
  by (clarsimp simp: all_active_tcb_ptrs_def is_active_tcb_ptr_def) wp

lemma setCurThread_almost_no_orphans:
  "\<lbrace>\<lambda>s. almost_no_orphans t s \<and>
          (ksCurThread s \<noteq> t \<longrightarrow>
             ksCurThread s \<in> all_active_tcb_ptrs s \<longrightarrow>
             ksCurThread s \<in> all_queued_tcb_ptrs s)\<rbrace>
   setCurThread t \<lbrace>\<lambda>_. no_orphans\<rbrace>"
  unfolding setCurThread_def
  apply wp
  apply (fastforce simp: almost_no_orphans_def
                        no_orphans_def
                        all_queued_tcb_ptrs_def
                        all_active_tcb_ptrs_def
                        is_active_tcb_ptr_def)
  done

lemmas ArchThreadDecls_H_switchToThread_all_active_tcb_ptrs[wp] =
  st_tcb_at'_all_active_tcb_ptrs_lift [OF Arch_switchToThread_st_tcb']

lemmas ArchThreadDecls_H_switchToThread_all_queued_tcb_ptrs_lift[wp] =
  ksQ_all_queued_tcb_ptrs_lift [OF arch_switch_thread_ksQ]

lemma ThreadDecls_H_switchToThread_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<and>
         st_tcb_at' runnable' tcb_ptr s \<and>
         (ksCurThread s \<in> all_active_tcb_ptrs s
            \<longrightarrow> ksCurThread s \<in> all_queued_tcb_ptrs s)\<rbrace>
   ThreadDecls_H.switchToThread tcb_ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding Thread_H.switchToThread_def
  apply (wp setCurThread_almost_no_orphans
            tcbSchedDequeue_almost_no_orphans)
   apply (wps tcbSchedDequeue_ct')
   apply (wp tcbSchedDequeue_all_queued_tcb_ptrs hoare_convert_imp)
    apply (wps)
    apply (wp)
    apply (wps)
    apply (wp)
  apply (clarsimp)
  done

lemma findM_failure':
  "\<lbrakk> \<And>x S. \<lbrace> \<lambda>s. P S s \<rbrace> f x \<lbrace> \<lambda>rv s. \<not> rv \<longrightarrow> P (insert x S) s \<rbrace> \<rbrakk> \<Longrightarrow>
   \<lbrace> \<lambda>s. P S s \<rbrace> findM f xs \<lbrace> \<lambda>rv s. rv = None \<longrightarrow> P (S \<union> set xs) s \<rbrace>"
  apply (induct xs arbitrary: S)
   apply (clarsimp, wp, clarsimp)
  apply clarsimp
  apply (rule hoare_seq_ext[rotated], assumption)
  apply (case_tac r)
   apply (clarsimp, wp, clarsimp)
  apply clarsimp
  apply (rule hoare_strengthen_post, assumption)
  apply clarsimp
  done

lemmas findM_failure = findM_failure'[where S="{}", simplified]

lemma tcbSchedEnqueue_inQueue_eq:
  "\<lbrace> valid_queues' and K (tcb_ptr = tcb_ptr') \<rbrace>
   tcbSchedEnqueue tcb_ptr
   \<lbrace> \<lambda>rv s. tcb_ptr' \<in> all_queued_tcb_ptrs s \<rbrace>"
  apply (rule hoare_gen_asm, simp)
  apply wp
  done

lemma findM_on_success:
  "\<lbrakk> \<And>x. \<lbrace> P x \<rbrace> f x \<lbrace> \<lambda>rv s. rv \<rbrace>; \<And>x y. \<lbrace> P x \<rbrace> f y \<lbrace> \<lambda>rv. P x \<rbrace> \<rbrakk> \<Longrightarrow>
   \<lbrace> \<lambda>s. \<exists>x \<in> set xs. P x s \<rbrace> findM f xs \<lbrace> \<lambda>rv s. \<exists> y. rv = Some y \<rbrace>"
  apply (induct xs)
   apply clarsimp
  apply clarsimp
  apply wp
   apply assumption
  apply (clarsimp simp: imp_conv_disj Bex_def)
  apply (wp hoare_vcg_disj_lift hoare_ex_wp | clarsimp)+
  done

crunch st_tcb' [wp]: switchToThread "\<lambda>s. P' (st_tcb_at' P t s)"
  (ignore: MachineOps.clearExMonitor)

lemma setQueue_deq_not_empty:
  "\<lbrace> \<lambda>s. (\<exists>tcb. tcb \<in> set (ksReadyQueues s p) \<and> st_tcb_at' P tcb s) \<and>
         (\<exists>tcb_ptr. \<not> st_tcb_at' P tcb_ptr s \<and>
                    queue = [x\<leftarrow>((ksReadyQueues s) (d, priority)). x \<noteq> tcb_ptr]) \<rbrace>
   setQueue d priority queue
   \<lbrace> \<lambda>rv s. \<exists>tcb. tcb \<in> set (ksReadyQueues s p) \<and> st_tcb_at' P tcb s \<rbrace>"
  unfolding setQueue_def
  apply wp
  apply auto
  done

lemma tcbSchedDequeue_not_empty:
  "\<lbrace> \<lambda>s. (\<exists>tcb. tcb \<in> set (ksReadyQueues s p) \<and> st_tcb_at' P tcb s) \<and> \<not> st_tcb_at' P thread s \<rbrace>
   tcbSchedDequeue thread
   \<lbrace> \<lambda>rv s. \<exists>tcb. tcb \<in> set (ksReadyQueues s p) \<and> st_tcb_at' P tcb s \<rbrace>"
  unfolding tcbSchedDequeue_def
  apply wp
      apply (wp hoare_ex_wp threadSet_st_tcb_no_state)
      apply clarsimp
     apply (wp setQueue_deq_not_empty)
   apply (rule_tac Q="\<lambda>rv s. \<not> st_tcb_at' P thread s" in hoare_post_imp)
    apply fastforce
   apply (wp weak_if_wp | clarsimp)+
  done

lemmas switchToThread_all_active_tcb_ptrs[wp] =
  st_tcb_at'_all_active_tcb_ptrs_lift [OF switchToThread_st_tcb']

(* ksSchedulerAction s = ChooseNewThread *)
lemma chooseThread_no_orphans [wp]:
  notes hoare_TrueI[simp]
  shows
  "\<lbrace>\<lambda>s. no_orphans s \<and> all_invs_but_ct_idle_or_in_cur_domain' s \<and>
          (is_active_tcb_ptr (ksCurThread s) s
             \<longrightarrow> ksCurThread s \<in> all_queued_tcb_ptrs s)\<rbrace>
   chooseThread
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  (is "\<lbrace>?PRE\<rbrace> _ \<lbrace>_\<rbrace>")
  apply (clarsimp simp: chooseThread_def cong: if_cong)
  apply (wp | clarsimp)+

   apply (rule_tac I="all_invs_but_ct_idle_or_in_cur_domain'" in findM_on_outcome)
   apply (clarsimp)
   apply (wp, wpc)
     apply (wp static_imp_wp)
     apply (rule ThreadDecls_H_switchToThread_no_orphans)
    apply (simp only: not_True_eq_False simp_thms)
    apply (rule wp_post_taut)
   apply (clarsimp)+
   apply (rule_tac Q="\<lambda>ksq s. (\<forall>t\<in>set(ksq). st_tcb_at' runnable' t s) \<and> ?PRE s"
            in hoare_post_imp)
    apply (fastforce simp: all_active_tcb_ptrs_def)
   apply (wp gq_wp)
   apply (fastforce simp: all_invs_but_ct_idle_or_in_cur_domain'_def valid_state'_def
                          valid_queues_def st_tcb_at'_def
                   elim!: obj_at'_weakenE)
  apply (wp | clarsimp)+
  done

lemma hoare_neg_imps:
  "\<lbrace>P\<rbrace> f \<lbrace>\<lambda> rv s. \<not> R rv s\<rbrace> \<Longrightarrow> \<lbrace>P\<rbrace> f \<lbrace>\<lambda>r s. R r s \<longrightarrow> Q r s\<rbrace>"
  by (auto simp: valid_def)

lemma setCurThread_ct [wp]:
  "\<lbrace> \<top> \<rbrace>
   setCurThread tcb_ptr
   \<lbrace> \<lambda>rv s. ksCurThread s = tcb_ptr \<rbrace>"
  unfolding setCurThread_def
  apply (wp | clarsimp)+
  done

lemma ThreadDecls_H_switchToThread_ct [wp]:
  "\<lbrace> \<top> \<rbrace>
   ThreadDecls_H.switchToThread tcb_ptr
   \<lbrace> \<lambda>rv s. ksCurThread s = tcb_ptr \<rbrace>"
  unfolding switchToThread_def
  apply (wp | clarsimp)+
  done

crunch no_orphans [wp]: nextDomain no_orphans
(wp: no_orphans_lift simp: Let_def)

crunch ksQ [wp]: nextDomain "\<lambda>s. P (ksReadyQueues s p)"
(simp: Let_def)

crunch st_tcb_at' [wp]: nextDomain "\<lambda>s. P (st_tcb_at' P' p s)"
(simp: Let_def)

crunch ct' [wp]: nextDomain "\<lambda>s. P (ksCurThread s)"
(simp: Let_def)

crunch sch_act_not [wp]: nextDomain "sch_act_not t"
(simp: Let_def)

lemma tcbSchedEnqueue_in_ksQ':
  "\<lbrace>valid_queues' and tcb_at' t and K (t = t')\<rbrace>
     tcbSchedEnqueue t'
   \<lbrace>\<lambda>r s. \<exists>domain priority. t \<in> set (ksReadyQueues s (domain, priority))\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (wp tcbSchedEnqueue_in_ksQ | clarsimp)+
  done

lemma all_invs_but_ct_idle_or_in_cur_domain'_strg:
  "invs' s \<longrightarrow> all_invs_but_ct_idle_or_in_cur_domain' s"
  by (clarsimp simp: invs'_to_invs_no_cicd'_def)

lemma schedule_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_wf (ksSchedulerAction s) s \<rbrace>
   schedule
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding schedule_def
  apply (wp, wpc)
       -- "action = ResumeCurrentThread"
      apply (wp)[1]
     -- "action = ChooseNewThread"
     apply (clarsimp simp: when_def)
     apply (wp ssa_no_orphans hoare_vcg_all_lift)
         apply (wp hoare_disjI1 chooseThread_nosch)
         apply (wp nextDomain_invs_no_cicd' hoare_vcg_imp_lift
                   hoare_lift_Pf2 [OF ksQ_all_queued_tcb_ptrs_lift
                                      [OF nextDomain_ksQ]
                                      nextDomain_ct']
                   hoare_lift_Pf2 [OF st_tcb_at'_is_active_tcb_ptr_lift
                                    [OF nextDomain_st_tcb_at']
                                    nextDomain_ct']
                   hoare_vcg_all_lift getDomainTime_wp)[2]
       apply ((wp tcbSchedEnqueue_no_orphans tcbSchedEnqueue_in_ksQ'
                  hoare_drop_imp
             | clarsimp simp: all_queued_tcb_ptrs_def
             | strengthen all_invs_but_ct_idle_or_in_cur_domain'_strg
             | wps tcbSchedEnqueue_ct')+)[2]
     apply wp[1]
    -- "action = SwitchToThread word"
    apply (rename_tac word)
    apply (wp ssa_no_orphans hoare_vcg_all_lift
              ThreadDecls_H_switchToThread_no_orphans)
      apply (rule_tac Q="\<lambda>_ s. (t=word \<longrightarrow> ksCurThread s = word) \<and>
                               (t\<noteq>word \<longrightarrow> sch_act_not t s)"
             in hoare_post_imp, clarsimp)
      apply (wp stt_nosch static_imp_wp)
     apply (wp tcbSchedEnqueue_no_orphans hoare_drop_imp)
      apply (rule_tac Q="\<lambda>_ s. \<exists>p. curThread \<in> set (ksReadyQueues s p)
                               \<and> curThread = ksCurThread s"
               in hoare_post_imp, clarsimp simp: all_queued_tcb_ptrs_def)
      apply (wps tcbSchedEnqueue_ct')
      apply clarsimp
      apply (wp tcbSchedEnqueue_in_ksQ)[1]
     apply (wp)
  apply (case_tac "ksSchedulerAction s")
    apply (clarsimp)
   apply (clarsimp simp: st_tcb_at'_def is_active_tcb_ptr_def)
   apply (rule conjI, clarsimp simp: invs'_def valid_state'_def cur_tcb'_def)
   apply (clarsimp simp: is_active_thread_state_def comp_def
                         all_invs_but_ct_idle_or_in_cur_domain'_strg)
   apply (drule(1) obj_at_not_obj_at_conj)
   apply (subgoal_tac "obj_at' (\<lambda>_. False) (ksCurThread s) s", clarsimp)
   apply (erule obj_at'_weakenE)
   apply (case_tac "tcbState k", (clarsimp simp: isRunning_def isRestart_def)+)
  apply (rule conjI, clarsimp simp: invs'_def valid_state'_def cur_tcb'_def)
  apply (clarsimp simp: st_tcb_at'_def all_active_tcb_ptrs_def comp_def
                        is_active_thread_state_def is_active_tcb_ptr_def)
  apply (drule(1) obj_at_not_obj_at_conj)
  apply (subgoal_tac "obj_at' (\<lambda>_. False) (ksCurThread s) s", clarsimp)
  apply (erule obj_at'_weakenE)
  apply (case_tac "tcbState k", (clarsimp simp: isRunning_def isRestart_def)+)
  done

lemma setAsyncEP_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   setAsyncEP p aep
   \<lbrace> \<lambda>_ s. no_orphans s \<rbrace>"
  apply (rule no_orphans_lift)
      apply (wp | clarsimp simp: setAsyncEP_def updateObject_default_def)+
  done

crunch no_orphans [wp]: doMachineOp "no_orphans"
(wp: no_orphans_lift)

crunch no_orphans [wp]: setMessageInfo "no_orphans"

crunch no_orphans [wp]: doAsyncTransfer "no_orphans"
(simp: crunch_simps wp: crunch_wps)

crunch ksReadyQueues [wp]: doAsyncTransfer "\<lambda>s. P (ksReadyQueues s)"
(simp: crunch_simps wp: crunch_wps)

crunch st_tcb' [wp]: doAsyncTransfer "st_tcb_at' (\<lambda>st. P st) t"

crunch valid_queues' [wp]: doAsyncTransfer "valid_queues'"

lemma doAsyncTransfer_almost_no_orphans [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans target s \<rbrace> 
   doAsyncTransfer badge msgWord thread
   \<lbrace> \<lambda>rv s. almost_no_orphans target s \<rbrace>"
  unfolding almost_no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

lemma possibleSwitchTo_almost_no_orphans [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans target s \<and> valid_queues' s \<and> st_tcb_at' runnable' target s \<rbrace>
   possibleSwitchTo target onSamePriority
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding possibleSwitchTo_def
  apply (wp tcbSchedEnqueue_almost_no_orphans ssa_almost_no_orphans static_imp_wp | wpc | clarsimp)+
    apply (wp hoare_drop_imps | clarsimp)+
  done

lemma attemptSwitchTo_almost_no_orphans [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans target s \<and> valid_queues' s \<and> st_tcb_at' runnable' target s \<rbrace> 
   attemptSwitchTo target
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding attemptSwitchTo_def
  apply wp
  done

lemma switchIfRequiredTo_schedule_no_orphans [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans target s \<and> valid_queues' s \<and> st_tcb_at' runnable' target s \<rbrace>
   switchIfRequiredTo target
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding switchIfRequiredTo_def by wp

lemma sendAsyncIPC_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<rbrace>
   sendAsyncIPC aepptr badge val
   \<lbrace> \<lambda>_ s. no_orphans s \<rbrace>"
  unfolding sendAsyncIPC_def
  apply (rule hoare_pre)
   apply (wp hoare_drop_imps hoare_vcg_all_lift sts_st_tcb' | wpc | clarsimp)+
  done 

lemma tcbSchedAppend_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   tcbSchedAppend thread
   \<lbrace> \<lambda>_ s. no_orphans s \<rbrace>"
  unfolding tcbSchedAppend_def
  apply (wp setQueue_no_orphans_enq threadSet_no_orphans weak_if_wp
            | clarsimp simp: unless_def | simp only: subset_insertI)+
  done

lemma tcbSchedAppend_almost_no_orphans:
  "\<lbrace> \<lambda>s. almost_no_orphans thread s \<and> valid_queues' s \<rbrace>
   tcbSchedAppend thread
   \<lbrace> \<lambda>_ s. no_orphans s \<rbrace>"
  unfolding tcbSchedAppend_def
  apply (wp setQueue_almost_no_orphans_enq[where tcb_ptr=thread] threadSet_no_orphans
            | clarsimp simp: unless_def | simp only: subset_insertI)+
  apply (unfold threadGet_def)
  apply (wp getObject_tcb_wp | clarsimp)+
  apply (drule obj_at_ko_at', clarsimp)
  apply (rule_tac x=ko in exI)
  apply (clarsimp simp: almost_no_orphans_def no_orphans_def)
  apply (drule queued_in_queue | simp)+
  apply (auto simp: all_queued_tcb_ptrs_def)
  done

lemma no_orphans_is_almost[simp]:
  "no_orphans s \<Longrightarrow> almost_no_orphans t s"
  by (clarsimp simp: no_orphans_def almost_no_orphans_def)

crunch no_orphans [wp]: decDomainTime no_orphans
(wp: no_orphans_lift)

crunch valid_queues' [wp]: decDomainTime valid_queues'

lemma timerTick_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<rbrace>
   timerTick
   \<lbrace> \<lambda>_ s. no_orphans s \<rbrace>"
  unfolding timerTick_def getDomainTime_def numDomains_def
  apply (rule hoare_pre)
   apply (wp hoare_drop_imps | clarsimp)+
   apply (wp threadSet_valid_queues' tcbSchedAppend_almost_no_orphans
             threadSet_almost_no_orphans threadSet_no_orphans tcbSchedAppend_sch_act_wf
             | wpc | clarsimp)+
         apply (rule_tac Q="\<lambda>rv s. no_orphans s \<and> valid_queues' s \<and> tcb_at' thread s
                                 \<and> sch_act_wf  (ksSchedulerAction s) s" in hoare_post_imp)
          apply (clarsimp simp: inQ_def)
         apply (wp hoare_drop_imps | clarsimp)+
  apply auto
  done

lemma handleInterrupt_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<rbrace>
   handleInterrupt irq
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding handleInterrupt_def
  apply (rule hoare_pre)
   apply (wp hoare_drop_imps hoare_vcg_all_lift getIRQState_inv | wpc | clarsimp)+
  done

lemma handleDoubleFault_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<rbrace>
   handleDoubleFault tptr ex1 ex2
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding handleDoubleFault_def
  apply (wp setThreadState_not_active_no_orphans
         | clarsimp simp: is_active_thread_state_def isRestart_def isRunning_def)+
  done

crunch st_tcb' [wp]: getThreadCallerSlot "st_tcb_at' (\<lambda>st. P st) t"

crunch st_tcb' [wp]: getThreadReplySlot "st_tcb_at' (\<lambda>st. P st) t"

crunch no_orphans [wp]: cteInsert "no_orphans"
(wp: crunch_wps)

crunch no_orphans [wp]: getThreadCallerSlot "no_orphans"

crunch no_orphans [wp]: getThreadReplySlot "no_orphans"

lemma setupCallerCap_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<rbrace>
   setupCallerCap sender receiver
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setupCallerCap_def
  apply (wp setThreadState_not_active_no_orphans
         | clarsimp simp: is_active_thread_state_def isRestart_def isRunning_def)+
  done

crunch almost_no_orphans [wp]: cteInsert "almost_no_orphans tcb_ptr"
(wp: crunch_wps)

crunch almost_no_orphans [wp]: getThreadCallerSlot "almost_no_orphans tcb_ptr"

crunch almost_no_orphans [wp]: getThreadReplySlot "almost_no_orphans tcb_ptr"

lemma setupCallerCap_almost_no_orphans [wp]:
  "\<lbrace> \<lambda>s. almost_no_orphans tcb_ptr s \<and> valid_queues' s \<rbrace>
   setupCallerCap sender receiver
   \<lbrace> \<lambda>rv s. almost_no_orphans tcb_ptr s \<rbrace>"
  unfolding setupCallerCap_def
  apply (wp setThreadState_not_active_almost_no_orphans
         | clarsimp simp: is_active_thread_state_def isRestart_def isRunning_def)+
  done

crunch ksReadyQueues [wp]: doIPCTransfer "\<lambda>s. P (ksReadyQueues s)"
(wp: transferCapsToSlots_pres1 crunch_wps)

crunch no_orphans [wp]: doIPCTransfer "no_orphans"
(wp: no_orphans_lift)

crunch ksQ'[wp]: setEndpoint "\<lambda>s. P (ksReadyQueues s)"
  (wp: setObject_queues_unchanged_tcb updateObject_default_inv)

crunch no_orphans [wp]: setEndpoint "no_orphans"
  (wp: no_orphans_lift)

lemma sendIPC_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<and> sch_act_wf (ksSchedulerAction s) s \<rbrace>
   sendIPC blocking call badge canGrant thread epptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding sendIPC_def
  apply (wp hoare_drop_imps setThreadState_not_active_no_orphans sts_st_tcb' | wpc
         | clarsimp simp: is_active_thread_state_def isRestart_def isRunning_def)+
  apply (rule_tac Q="\<lambda>rv. no_orphans and valid_queues' and valid_objs' and ko_at' rv epptr
                          and (\<lambda>s. sch_act_wf (ksSchedulerAction s) s)" in hoare_post_imp)
   apply (fastforce simp: valid_objs'_def valid_obj'_def valid_ep'_def obj_at'_def projectKOs)
  apply (wp get_ep_sp' | clarsimp)+
  done

lemma sendFaultIPC_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<and> sch_act_wf (ksSchedulerAction s) s \<rbrace>
   sendFaultIPC tptr fault
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding sendFaultIPC_def
  apply (rule hoare_pre)
   apply (wp threadSet_valid_queues' threadSet_no_orphans threadSet_valid_objs'
             threadSet_sch_act | wpc | clarsimp)+
    apply (rule_tac Q'="\<lambda>handlerCap s. no_orphans s \<and> valid_queues' s
                                         \<and> valid_objs' s
                                         \<and> sch_act_wf (ksSchedulerAction s) s"
             in hoare_post_imp_R)
     apply (wp | clarsimp simp: inQ_def valid_tcb'_def tcb_cte_cases_def)+
  done

lemma sendIPC_valid_queues' [wp]:
  "\<lbrace> \<lambda>s. valid_queues' s \<and> valid_objs' s \<and> sch_act_wf (ksSchedulerAction s) s \<rbrace>
   sendIPC blocking call badge canGrant thread epptr
   \<lbrace> \<lambda>rv s. valid_queues' s \<rbrace>"
  unfolding sendIPC_def
  apply (wp hoare_drop_imps | wpc | clarsimp)+
          apply (wp_once sts_st_tcb', clarsimp)
         apply (wp)
  apply (rule_tac Q="\<lambda>rv. valid_queues' and valid_objs' and ko_at' rv epptr
                          and (\<lambda>s. sch_act_wf (ksSchedulerAction s) s)" in hoare_post_imp)
   apply (clarsimp)
  apply (wp get_ep_sp' | clarsimp)+
  done

lemma sendFaultIPC_valid_queues' [wp]:
  "\<lbrace> \<lambda>s. valid_queues' s \<and> valid_objs' s \<and> sch_act_wf (ksSchedulerAction s) s \<rbrace>
   sendFaultIPC tptr fault
   \<lbrace> \<lambda>rv s. valid_queues' s \<rbrace>"
  unfolding sendFaultIPC_def
  apply (rule hoare_pre)
   apply (wp threadSet_valid_queues' threadSet_valid_objs' threadSet_sch_act
          | wpc | clarsimp)+
    apply (rule_tac Q'="\<lambda>handlerCap s. valid_queues' s \<and> valid_objs' s
                                         \<and> sch_act_wf (ksSchedulerAction s) s"
             in hoare_post_imp_R)
     apply (wp | clarsimp simp: inQ_def valid_tcb'_def tcb_cte_cases_def)+
  done

lemma handleFault_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<and> sch_act_wf (ksSchedulerAction s) s \<rbrace>
   handleFault tptr ex1
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding handleFault_def
  apply (rule hoare_pre)
   apply (wp | clarsimp)+
  done

lemma replyFromKernel_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   replyFromKernel thread r
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (cases r, simp_all add: replyFromKernel_def)
  apply wp
  done

crunch ksSchedulerAction [wp]: setMessageInfo "\<lambda>s. P (ksSchedulerAction s)"

crunch ksCurThread [wp]: createNewCaps "\<lambda> s. P (ksCurThread s)"

crunch ksReadyQueues  [wp]: createNewCaps "\<lambda> s. P (ksReadyQueues s)"

crunch inv [wp]: alignError "P"

lemma createObjects_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> pspace_aligned' s \<and> pspace_no_overlap' ptr sz s \<and> pspace_distinct' s 
      \<and> n \<noteq> 0 \<and> range_cover ptr sz (objBitsKO (injectKOS val) + gbits) n
      \<and> \<not> case_option False (is_active_thread_state \<circ> tcbState) (projectKO_opt (injectKOS val)) \<rbrace>
   createObjects ptr n val gbits
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (clarsimp simp: no_orphans_def all_active_tcb_ptrs_def
                        is_active_tcb_ptr_def all_queued_tcb_ptrs_def)
  apply (simp only: imp_conv_disj st_tcb_at'_def createObjects_def)
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift createObjects_orig_obj_at2')
  apply clarsimp
  apply (erule(1) impE)
  apply clarsimp
  apply (drule_tac x = x in spec)
  apply (erule impE)
   apply (clarsimp simp:obj_at'_def)
  apply simp
done

lemma createWordObjects_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> pspace_aligned' s \<and> pspace_distinct' s 
   \<and> pspace_no_overlap' ptr sz s \<and> n \<noteq> 0 \<and> range_cover ptr sz (objBitsKO KOUserData + us) n\<rbrace>
   createWordObjects ptr n us
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding createWordObjects_def
  apply (wp | clarsimp simp: projectKO_opt_tcb)+
  apply (intro conjI,simp+)
  done

lemma copyGlobalMappings_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   copyGlobalMappings newPD
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

lemma no_orphans_update_simps[simp]:
  "no_orphans (gsCNodes_update f s) = no_orphans s"
  "no_orphans (gsUserPages_update g s) = no_orphans s"
  by (simp_all add: no_orphans_def all_active_tcb_ptrs_def
                    is_active_tcb_ptr_def all_queued_tcb_ptrs_def)

crunch no_orphans [wp]: insertNewCap "no_orphans"
(wp: hoare_drop_imps)

lemma createNewCaps_no_orphans:
  "\<lbrace> (\<lambda>s. no_orphans s 
         \<and>  pspace_aligned' s \<and> pspace_distinct' s
         \<and>  pspace_no_overlap' ptr sz s
         \<and>  (tp = APIObjectType ArchTypes_H.CapTableObject \<longrightarrow> us > 0))
         and K (range_cover ptr sz (APIType_capBits tp us) n \<and> 0 < n) \<rbrace> 
   createNewCaps tp ptr n us
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (clarsimp simp: createNewCaps_def toAPIType_def ArchTypes_H.toAPIType_def
    split del: split_if cong: option.case_cong)
  apply (cases tp, simp_all split del: split_if)
        apply (rename_tac apiobject_type)
        apply (case_tac apiobject_type, simp_all)
            apply (wp mapM_x_wp' threadSet_no_orphans
                   | clarsimp simp: is_active_thread_state_def makeObject_tcb
                                    projectKO_opt_tcb isRunning_def isRestart_def
                                    APIType_capBits_def objBits_simps Arch_createNewCaps_def
                   | fastforce simp:pageBits_def archObjSize_def ptBits_def pdBits_def)+
  done

lemma createObject_no_orphans:
  "\<lbrace>pspace_no_overlap' ptr sz and pspace_aligned' and pspace_distinct' and
    cte_wp_at' (\<lambda>cte. cteCap cte = (capability.UntypedCap ptr sz idx)) cref and
    K (range_cover ptr sz (APIType_capBits tp us) (Suc 0)) and no_orphans\<rbrace>
   RetypeDecls_H.createObject tp ptr us
   \<lbrace>\<lambda>xa. no_orphans\<rbrace>"
  apply (case_tac tp)
        apply (simp_all add:createObject_def ArchRetype_H.createObject_def)
        apply (rename_tac apiobject_type)
        apply (case_tac apiobject_type)
            apply (simp_all add:ArchRetype_H.createObject_def createPageObject_def placeNewObject_def2
              toAPIType_def ArchTypes_H.toAPIType_def placeNewObject_def2)+
            apply (wp threadSet_no_orphans | clarsimp)+
           apply ((wp createObjects'_wp_subst[where c = "makeObject::Structures_H.tcb"]
                  createObjects_no_orphans[where sz = sz] | 
             clarsimp simp: projectKO_opt_tcb cte_wp_at_ctes_of projectKO_opt_ep
             is_active_thread_state_def makeObject_tcb
             projectKO_opt_tcb isRunning_def isRestart_def
             APIType_capBits_def objBits_simps split:option.splits)+)[1]
          apply ((wp createObjects'_wp_subst[where c = "makeObject::Structures_H.endpoint"]
                  createObjects_no_orphans[where sz = sz] | 
          clarsimp simp: projectKO_opt_tcb cte_wp_at_ctes_of projectKO_opt_ep
          is_active_thread_state_def makeObject_tcb
          projectKO_opt_tcb isRunning_def isRestart_def
          APIType_capBits_def objBits_simps split:option.splits)+)[1]
         apply ((wp createObjects'_wp_subst[where c = "makeObject::async_endpoint"]
                  createObjects_no_orphans[where sz = sz] | 
          clarsimp simp: projectKO_opt_tcb cte_wp_at_ctes_of projectKO_opt_ep
          is_active_thread_state_def makeObject_tcb
          projectKO_opt_tcb isRunning_def isRestart_def
          APIType_capBits_def objBits_simps split:option.splits)+)[1]
        apply ((wp createObjects'_wp_subst[where c = "makeObject::cte"]
                   createObjects_no_orphans[where sz = sz] | 
         clarsimp simp: projectKO_opt_tcb cte_wp_at_ctes_of projectKO_opt_ep
         is_active_thread_state_def makeObject_tcb
         projectKO_opt_tcb isRunning_def isRestart_def
         APIType_capBits_def objBits_simps split:option.splits)+)[1]
       apply ((wp createObjects'_wp_subst[where c = "makeObject::user_data"]
                createObjects_no_orphans[where sz = sz] | 
        clarsimp simp: projectKO_opt_tcb cte_wp_at_ctes_of projectKO_opt_ep
        is_active_thread_state_def makeObject_tcb pageBits_def
        projectKO_opt_tcb isRunning_def isRestart_def
        APIType_capBits_def objBits_simps split:option.splits)+)[4]
   apply ((wp createObjects'_wp_subst[where c = "makeObject::pte"]
               createObjects_no_orphans[where sz = sz ] | 
       clarsimp simp: projectKO_opt_tcb cte_wp_at_ctes_of projectKO_opt_ep
       is_active_thread_state_def makeObject_tcb pageBits_def ptBits_def
       projectKO_opt_tcb isRunning_def isRestart_def archObjSize_def
       APIType_capBits_def objBits_simps split:option.splits)+)[1]
  apply ((wp createObjects'_wp_subst[where c = "makeObject::pde"]
              createObjects_no_orphans[where sz = sz] | 
      clarsimp simp: projectKO_opt_tcb cte_wp_at_ctes_of projectKO_opt_ep
      is_active_thread_state_def makeObject_tcb pageBits_def ptBits_def pdBits_def
      projectKO_opt_tcb isRunning_def isRestart_def archObjSize_def
      APIType_capBits_def objBits_simps split:option.splits))+
  done

lemma createNewObjects_no_orphans :
  "\<lbrace>\<lambda>s. no_orphans s \<and> invs' s \<and> pspace_no_overlap' ptr sz s
         \<and> (\<forall>slot\<in>set slots. cte_wp_at' (\<lambda>c. cteCap c = capability.NullCap) slot s)
         \<and> cte_wp_at' (\<lambda>cte. cteCap cte = UntypedCap (ptr && ~~ mask sz) sz idx) cref s
         \<and> caps_no_overlap'' ptr sz s
         \<and> range_cover ptr sz (APIType_capBits tp us) (length slots) 
         \<and> (tp = APIObjectType ArchTypes_H.CapTableObject \<longrightarrow> us > 0)
         \<and> caps_overlap_reserved' {ptr..ptr + of_nat (length slots) * 2 ^ APIType_capBits tp us - 1} s
         \<and> slots \<noteq> [] \<and> distinct slots \<and> ptr \<noteq> 0\<rbrace>
   createNewObjects tp cref slots ptr us
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (rule hoare_name_pre_state)
  apply clarsimp
  apply (rule hoare_pre)
   apply (rule createNewObjects_wp_helper)
       apply simp+
   apply (simp add:insertNewCaps_def)
   apply wp
    apply (rule_tac P = "length caps = length slots" in hoare_gen_asm)
    apply (wp zipWithM_x_inv)
    apply simp
   apply (wp createNewCaps_no_orphans[where sz = sz] | clarsimp)+ 
   apply (rule hoare_strengthen_post[OF createNewCaps_ret_len])
   apply simp
  apply (clarsimp simp:invs_pspace_aligned' invs_valid_pspace' invs_pspace_distinct')
  apply (intro conjI)
     apply (erule range_cover.range_cover_n_less[where 'a=32, folded word_bits_def])
    apply (clarsimp simp:cte_wp_at_ctes_of)
   apply (simp add:invs'_def valid_state'_def)
  apply (simp add: invs_ksCurDomain_maxDomain')
  done

lemma ksMachineState_ksPSpace_upd_comm:
  "ksPSpace_update g (ksMachineState_update f s) =
   ksMachineState_update f (ksPSpace_update g s)"
by simp

lemma deleteObjects_no_orphans [wp]:
  "\<lbrace> (\<lambda>s. no_orphans s \<and> pspace_distinct' s) and K (is_aligned ptr bits) \<rbrace>
   deleteObjects ptr bits
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (rule hoare_gen_asm)
  apply (unfold deleteObjects_def2 doMachineOp_def split_def)
  apply (wp hoare_drop_imps | clarsimp)+
  apply (clarsimp simp: no_orphans_def all_active_tcb_ptrs_def
                        all_queued_tcb_ptrs_def is_active_tcb_ptr_def
                        ksMachineState_ksPSpace_upd_comm)
  apply (drule_tac x=tcb_ptr in spec)
  apply (clarsimp simp: st_tcb_at'_def obj_at_delete'[unfolded field_simps]
                  cong: if_cong)
  done

lemma invokeUntyped_no_orphans' [wp]:
  "ui = Retype cref ptr_base ptr tp us slots \<Longrightarrow>
   \<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> valid_untyped_inv' ui s \<and> ct_active' s \<rbrace>
   invokeUntyped ui 
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  apply (rule hoare_name_pre_state)
  apply clarsimp
  apply (subgoal_tac "invokeUntyped_proofs s cref ptr tp us slots sz idx")
  prefer 2
   apply (simp add:invokeUntyped_proofs_def)
  proof -
    fix s sz idx
    assume no_orph: "no_orphans s"
    assume misc : " (tp = APIObjectType ArchTypes_H.apiobject_type.CapTableObject \<longrightarrow> 0 < us)"
                  " tp = APIObjectType ArchTypes_H.apiobject_type.Untyped \<longrightarrow> 4 \<le> us \<and> us \<le> 30"
                  " sch_act_simple s " "ct_active' s"
    assume ivk_pf: "invokeUntyped_proofs s cref ptr tp us slots sz idx"
    note blah[simp del] = 
          atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
          Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex usableUntypedRange.simps

    have capBits_low_bound[simp]:
      "4 \<le> APIType_capBits tp us"
       using misc
       apply (case_tac tp)
       apply (simp_all add:APIType_capBits_def objBits_simps ArchTypes_H.apiobject_type.splits)
       done

    have us_align[simp]:"is_aligned (of_nat (length slots) * 2 ^ APIType_capBits tp us) 4"
      apply (rule is_aligned_weaken)
       apply (subst mult.commute)
       apply (rule is_aligned_shiftl_self[unfolded shiftl_t2n])
      apply simp
      done

  show "\<lbrace>op = s\<rbrace> invokeUntyped (Invocations_H.untyped_invocation.Retype cref (ptr && ~~ mask sz) ptr tp us slots) 
          \<lbrace>\<lambda>reply. no_orphans\<rbrace>"
  apply (simp add: invokeUntyped_def insertNewCaps_def
                   split_def bind_assoc zipWithM_x_mapM
              cong: capability.case_cong)
  apply (case_tac "ptr && ~~ mask sz \<noteq> ptr")
   apply (rule hoare_pre)
    apply (wp createNewObjects_no_orphans[where sz = sz] getSlotCap_wp 
              updateFreeIndex_invs' updateFreeIndex_pspace_no_overlap'
              hoare_vcg_ball_lift updateCap_weak_cte_wp_at
              updateFreeIndex_caps_no_overlap''
              updateFreeIndex_caps_overlap_reserved' | clarsimp)+
   apply (intro exI)
   apply (rule conjI)
    apply (rule invokeUntyped_proofs.cte_wp_at'[OF ivk_pf])
   using ivk_pf
   apply (clarsimp simp:conj_comms invs_valid_pspace'
          invokeUntyped_proofs_def no_orph misc)
   apply (simp add:getFreeIndex_def add_minus_neg_mask field_simps shiftL_nat
                   invokeUntyped_proofs.ps_no_overlap'[OF ivk_pf]
                   invokeUntyped_proofs.not_0_ptr[OF ivk_pf]
                   invokeUntyped_proofs.usableRange_disjoint[OF ivk_pf]
                   invokeUntyped_proofs.descendants_range[OF ivk_pf]
                   invokeUntyped_proofs.slots_invD[OF ivk_pf]
                   invokeUntyped_proofs.caps_no_overlap'[OF ivk_pf])
   apply (intro conjI)
       apply (simp add: range_cover_unat
                        range_cover.unat_of_nat_shift field_simps)+
      apply (drule range_cover.range_cover_compare_bound)
      apply simp
     apply (rule aligned_add_aligned[OF aligned_after_mask])
       apply (erule range_cover.aligned)
      apply simp
     apply (simp add:range_cover_def)
    apply simp+
   apply (rule subset_trans[OF invokeUntyped_proofs.subset_stuff[OF ivk_pf]])
   apply (clarsimp simp:blah word_and_le2)
  using ivk_pf
  apply clarsimp
  apply (wp createNewObjects_no_orphans[where sz = sz] getSlotCap_wp 
              updateFreeIndex_invs_simple' updateFreeIndex_pspace_no_overlap'
              hoare_vcg_ball_lift updateCap_weak_cte_wp_at
              updateFreeIndex_caps_no_overlap''
              updateFreeIndex_caps_overlap_reserved' | clarsimp)+
   apply (strengthen impI[OF invs_pspace_aligned'] impI[OF invs_valid_pspace']
          impI[OF invs_pspace_distinct'] impI[OF invs_arch_state] impI[OF invs_psp_aligned])
   apply (clarsimp simp:conj_comms invokeUntyped_proofs.slots_invD[OF ivk_pf])
   apply (rule_tac P = "cap = capability.UntypedCap (ptr && ~~ mask sz) sz idx" 
       in hoare_gen_asm)
   apply (clarsimp simp:misc)
   apply (wp deleteObjects_invs'[where idx = idx and p = "cref"] 
     deleteObjects_caps_no_overlap''[where idx = idx and slot = "cref"] 
     deleteObject_no_overlap[where idx = idx]
     deleteObjects_cte_wp_at'[where idx = idx and ptr = ptr and bits = sz]
     deleteObjects_caps_overlap_reserved'[where idx = idx and slot = "cref"] 
     deleteObjects_descendants[where idx = idx and p = "cref"]
     hoare_vcg_ball_lift hoare_drop_imp hoare_vcg_ex_lift 
     deleteObjects_st_tcb_at'[where p = cref]
     deleteObjects_cte_wp_at'[where idx = idx and ptr = ptr and bits = sz]
     deleteObjects_ct_active'[where idx = idx and cref = cref])
   apply (clarsimp simp:conj_comms)
   apply (wp getSlotCap_wp)
   using invokeUntyped_proofs.usableRange_disjoint[OF ivk_pf]
     invokeUntyped_proofs.descendants_range[OF ivk_pf]
     invokeUntyped_proofs.slots_invD[OF ivk_pf]
     invokeUntyped_proofs.vc'[OF ivk_pf]
     invokeUntyped_proofs.cref_inv[OF ivk_pf]
   apply (clarsimp simp:invs_valid_pspace' invokeUntyped_proofs_def
                        is_aligned_neg_mask_eq' range_cover.aligned
                        no_orph getFreeIndex_def misc range_cover.sz )
   apply (simp add: getFreeIndex_def add_minus_neg_mask field_simps shiftL_nat
                    invokeUntyped_proofs.not_0_ptr[OF ivk_pf]
                    descendants_range'_def2 shiftL_nat
                    range_cover_unat range_cover.unat_of_nat_shift
                    invokeUntyped_proofs.caps_no_overlap'[OF ivk_pf]
                    is_aligned_mask[unfolded is_aligned_neg_mask_eq'])
   apply (intro conjI)
       apply (simp add: range_cover_def word_bits_def)
      apply simp
     apply (drule range_cover.range_cover_compare_bound)
     apply (simp add:is_aligned_mask[unfolded is_aligned_neg_mask_eq'])
    apply (simp add:is_aligned_mask[symmetric])
   apply (rule subset_trans[OF invokeUntyped_proofs.subset_stuff[OF ivk_pf]])
   apply (simp add:is_aligned_mask[unfolded is_aligned_neg_mask_eq',symmetric])
  apply (clarsimp simp:misc no_orph invokeUntyped_proofs_def)
  done
qed

lemma invokeUntyped_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> valid_untyped_inv' ui s \<and> ct_active' s \<rbrace>
     invokeUntyped ui
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  by (cases ui, erule invokeUntyped_no_orphans')

lemma setInterruptState_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   setInterruptState a
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift | clarsimp)+
  done

crunch no_orphans [wp]: emptySlot "no_orphans"

lemma mapM_x_match:
  "\<lbrace>I and V xs\<rbrace> mapM_x m xs \<lbrace>\<lambda>rv. Q\<rbrace> \<Longrightarrow> \<lbrace>I and V xs\<rbrace> mapM_x m xs \<lbrace>\<lambda>rv. Q\<rbrace>"
  by assumption

lemma epCancelAll_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<rbrace>
    epCancelAll epptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding epCancelAll_def
  apply (wp sts_valid_objs' set_ep_valid_objs' sts_st_tcb'
            hoare_vcg_const_Ball_lift tcbSchedEnqueue_almost_no_orphans
             | wpc
             | rule mapM_x_match,
               rename_tac list,
               rule_tac V="\<lambda>_. valid_queues' and valid_objs'"
                    and I="no_orphans and (\<lambda>s. \<forall>t\<in>set list. tcb_at' t s)"
                     in mapM_x_inv_wp2
             | clarsimp simp: valid_tcb_state'_def)+
  apply (rule_tac Q="\<lambda>rv. no_orphans and valid_objs' and valid_queues' and ko_at' rv epptr"
                 in hoare_post_imp)
   apply (fastforce simp: valid_obj'_def valid_ep'_def obj_at'_def projectKOs)
  apply (wp get_ep_sp' | clarsimp)+
  done

lemma aepCancelAll_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<rbrace>
    aepCancelAll aep
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding aepCancelAll_def
  apply (wp sts_valid_objs' set_aep_valid_objs' sts_st_tcb'
            hoare_vcg_const_Ball_lift tcbSchedEnqueue_almost_no_orphans
             | wpc
             | clarsimp simp: valid_tcb_state'_def)+
    apply (rename_tac list)
    apply (rule_tac V="\<lambda>_. valid_queues' and valid_objs'"
                and I="no_orphans and (\<lambda>s. \<forall>t\<in>set list. tcb_at' t s)"
                in mapM_x_inv_wp2)
    apply simp
   apply (wp sts_valid_objs' set_aep_valid_objs' sts_st_tcb'
            hoare_vcg_const_Ball_lift tcbSchedEnqueue_almost_no_orphans|
          clarsimp simp: valid_tcb_state'_def)+
  apply (rule_tac Q="\<lambda>rv. no_orphans and valid_objs' and valid_queues' and ko_at' rv aep"
                 in hoare_post_imp)
   apply (fastforce simp: valid_obj'_def valid_aep'_def obj_at'_def projectKOs)
  apply (wp get_aep_sp' | clarsimp)+
  done

lemma finaliseCapTrue_standin_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<rbrace>
    finaliseCapTrue_standin cap final 
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding finaliseCapTrue_standin_def
  apply (rule hoare_pre)
   apply (wp | clarsimp)+
  done

lemma cteDeleteOne_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<rbrace>
   cteDeleteOne slot
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding cteDeleteOne_def
  apply (wp assert_inv isFinalCapability_inv weak_if_wp | clarsimp simp: unless_def)+
  done

crunch valid_objs' [wp]: getThreadReplySlot "valid_objs'"

lemma asyncIPCCancel_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<rbrace>
   asyncIPCCancel t aep
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding asyncIPCCancel_def Let_def
  apply (rule hoare_pre)
   apply (wp hoare_drop_imps setThreadState_not_active_no_orphans | wpc
          | clarsimp simp: is_active_thread_state_def isRestart_def isRunning_def)+
  done

lemma ipcCancel_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<and> valid_objs' s \<rbrace>
   ipcCancel t
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding ipcCancel_def Let_def
  apply (rule hoare_pre)
   apply (wp setThreadState_not_active_no_orphans hoare_drop_imps weak_if_wp
             threadSet_valid_queues' threadSet_valid_objs' threadSet_no_orphans | wpc
          | clarsimp simp: is_active_thread_state_def isRestart_def isRunning_def
                           inQ_def valid_tcb'_def tcb_cte_cases_def)+
  done

lemma suspend_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> tcb_at' t s \<rbrace>
   suspend t
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding suspend_def
  apply (wp | clarsimp simp: unless_def | rule conjI)+
    apply (clarsimp simp: is_active_tcb_ptr_def is_active_thread_state_def st_tcb_at_neg2)
    apply (wp setThreadState_not_active_no_orphans hoare_disjI1 setThreadState_st_tcb
           | clarsimp simp: is_active_thread_state_def isRunning_def isRestart_def)+
   apply (wp | strengthen invs_valid_queues' | clarsimp)+
  done

lemma storeHWASID_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   storeHWASID asid hw_asid
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

lemma invalidateHWASIDEntry_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   invalidateHWASIDEntry hwASID
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

lemma invalidateASID_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   invalidateASID asid
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

lemma findFreeHWASID_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   findFreeHWASID
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

crunch ksCurThread [wp]: invalidateASIDEntry "\<lambda> s. P (ksCurThread s)"

crunch ksReadyQueues[wp]: invalidateASIDEntry "\<lambda>s. P (ksReadyQueues s)"

lemma invalidateASIDEntry_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   invalidateASIDEntry asid
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

crunch no_orphans [wp]: flushSpace "no_orphans"

lemma deleteASIDPool_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   deleteASIDPool asid pool
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding deleteASIDPool_def
  apply (wp | clarsimp)+
     apply (rule_tac Q="\<lambda>rv s. no_orphans s" in hoare_post_imp)
      apply (clarsimp simp: no_orphans_def all_queued_tcb_ptrs_def
                            all_active_tcb_ptrs_def is_active_tcb_ptr_def)
     apply (wp mapM_wp_inv getObject_inv loadObject_default_inv | clarsimp)+
  done

lemma storePTE_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   storePTE ptr val
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

lemma storePDE_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   storePDE ptr val
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

crunch no_orphans [wp]: unmapPage "no_orphans"
(wp: crunch_wps ignore: getObject)

lemma flushTable_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   flushTable pd asid vptr
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  unfolding flushTable_def
  apply (wp hoare_drop_imps | wpc | clarsimp)+
  done

crunch no_orphans [wp]: unmapPageTable "no_orphans"

lemma setASIDPool_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   setObject p (ap :: asidpool)
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding no_orphans_disj all_queued_tcb_ptrs_def
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
  done

lemma deleteASID_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   deleteASID asid pd
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding deleteASID_def
  apply (wp getObject_inv loadObject_default_inv | wpc | clarsimp)+
  done

lemma arch_finaliseCap_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   ArchRetypeDecls_H.finaliseCap cap fin
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding ArchRetype_H.finaliseCap_def
  apply (rule hoare_pre)
   apply (wp | wpc | clarsimp)+
  done

lemma deletingIRQHandler_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<rbrace>
   deletingIRQHandler irq
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding deletingIRQHandler_def
  apply (wp, auto)
  done

lemma finaliseCap_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> valid_cap' cap s \<rbrace>
   finaliseCap cap final flag
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (simp add: finaliseCap_def Let_def
              cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply (wp | clarsimp simp: o_def)+
  apply (auto simp: valid_cap'_def dest!: isCapDs)
  done

lemma no_orphans_ksWorkUnits [simp]:
   "no_orphans (ksWorkUnitsCompleted_update f s) = no_orphans s"
  unfolding no_orphans_def all_active_tcb_ptrs_def all_queued_tcb_ptrs_def is_active_tcb_ptr_def
  apply auto
  done

crunch no_orphans [wp]: cteSwap "no_orphans"

crunch no_orphans [wp]: capSwapForDelete "no_orphans"

declare withoutPreemption_lift [wp del]

lemma reduceZombie_no_orphans:
  assumes fin:
  "\<And>s'' rv. \<lbrakk>\<not> (isZombie cap \<and> capZombieNumber cap = 0); \<not> (isZombie cap \<and> \<not> exposed); isZombie cap \<and> exposed;
              (Inr rv, s'')
              \<in> fst ((withoutPreemption $ locateSlot (capZombiePtr cap) (fromIntegral (capZombieNumber cap - 1))) st)\<rbrakk>
             \<Longrightarrow> s'' \<turnstile> \<lbrace>\<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s
                                   \<and> cte_wp_at' (\<lambda>cte. isZombie (cteCap cte)) slot s
                                   \<and> ex_cte_cap_to' rv s\<rbrace>
                         finaliseSlot rv False
                \<lbrace>\<lambda>rva s. no_orphans s \<and> invs' s \<and> sch_act_simple s
                            \<and> (fst rva \<longrightarrow> cte_wp_at' (\<lambda>cte. removeable' rv s (cteCap cte)) rv s)
                            \<and> (\<forall>irq sl'. snd rva = Some irq \<longrightarrow> sl' \<noteq> rv \<longrightarrow> cteCaps_of s sl' \<noteq> Some (IRQHandlerCap irq))\<rbrace>,
                \<lbrace>\<lambda>rv s. no_orphans s \<and> invs' s \<and> sch_act_simple s\<rbrace>"
  shows
  "st \<turnstile> \<lbrace>\<lambda>s.
      no_orphans s \<and> invs' s \<and> sch_act_simple s
              \<and> (exposed \<or> ex_cte_cap_to' slot s)
              \<and> cte_wp_at' (\<lambda>cte. cteCap cte = cap) slot s
              \<and> (exposed \<or> p = slot \<or>
                  cte_wp_at' (\<lambda>cte. (P and isZombie) (cteCap cte)
                                  \<or> (\<exists>zb n cp. cteCap cte = Zombie p zb n
                                       \<and> P cp \<and> (isZombie cp \<longrightarrow> capZombiePtr cp \<noteq> p))) p s)\<rbrace>
       reduceZombie cap slot exposed
   \<lbrace>\<lambda>rv s.
      no_orphans s \<and> invs' s \<and> sch_act_simple s
              \<and> (exposed \<or> ex_cte_cap_to' slot s)
              \<and> (exposed \<or> p = slot \<or>
                  cte_wp_at' (\<lambda>cte. (P and isZombie) (cteCap cte)
                                  \<or> (\<exists>zb n cp. cteCap cte = Zombie p zb n
                                       \<and> P cp \<and> (isZombie cp \<longrightarrow> capZombiePtr cp \<noteq> p))) p s)\<rbrace>,
   \<lbrace>\<lambda>rv s. no_orphans s \<and> invs' s \<and> sch_act_simple s\<rbrace>"
  apply (unfold reduceZombie_def cteDelete_def Let_def
                split_def fst_conv snd_conv haskell_fail_def
                case_Zombie_assert_fold)
  apply (rule hoare_pre_spec_validE)
   apply (wp hoare_vcg_disj_lift | simp)+
       apply (wp capSwap_cte_wp_cteCap getCTE_wp' | simp)+
           apply (wp shrink_zombie_invs')
         apply (rule getCTE_wp)
        apply (wp | simp)+
      apply (rule_tac Q="\<lambda>cte s. rv = capZombiePtr cap +
                                      of_nat (capZombieNumber cap) * 16 - 16
                              \<and> cte_wp_at' (\<lambda>c. c = cte) slot s \<and> invs' s
                              \<and> sch_act_simple s \<and> no_orphans s"
                  in hoare_post_imp)
       apply (clarsimp simp: cte_wp_at_ctes_of mult.commute mult.left_commute dest!: isCapDs)
       apply (simp add: field_simps)
      apply (wp getCTE_cte_wp_at)
      apply simp
      apply wp[1]
     apply (rule spec_strengthen_postE)
      apply (rule_tac Q="\<lambda>fc s. rv = capZombiePtr cap +
                                      of_nat (capZombieNumber cap) * 16 - 16"
                 in spec_valid_conj_liftE1)
       apply wp[1]
      apply (rule fin, assumption+)
     apply clarsimp
    apply (simp add: locateSlot_conv)
    apply ((wp | simp)+)[2]
  apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (rule conjI)
   apply (clarsimp dest!: isCapDs)
   apply (rule conjI)
    apply (erule(1) ex_Zombie_to)
     apply clarsimp
    apply clarsimp
   apply clarsimp
  apply (clarsimp simp: cte_level_bits_def dest!: isCapDs)
  apply (erule(1) ex_Zombie_to2)
   apply clarsimp+
  done

declare withoutPreemption_lift [wp]

lemma no_orphans_irq_state_independent[intro!, simp]:
  "no_orphans (s \<lparr>ksMachineState := ksMachineState s \<lparr> irq_state := f (irq_state (ksMachineState s)) \<rparr> \<rparr>)
   = no_orphans s"
  by (simp add: no_orphans_def all_active_tcb_ptrs_def 
                all_queued_tcb_ptrs_def is_active_tcb_ptr_def)

lemma finaliseSlot_no_orphans':
  "st \<turnstile> \<lbrace>\<lambda>s.
      no_orphans s \<and> invs' s \<and> sch_act_simple s 
              \<and> (exposed \<or> ex_cte_cap_to' slot s)
              \<and> (exposed \<or> p = slot \<or>
                  cte_wp_at' (\<lambda>cte. (P and isZombie) (cteCap cte)
                                  \<or> (\<exists>zb n cp. cteCap cte = Zombie p zb n
                                       \<and> P cp \<and> (isZombie cp \<longrightarrow> capZombiePtr cp \<noteq> p))) p s)\<rbrace>
       finaliseSlot' slot exposed
   \<lbrace>\<lambda>rv s.
      no_orphans s \<and> invs' s \<and> sch_act_simple s
              \<and> (exposed \<or> p = slot \<or>
                  cte_wp_at' (\<lambda>cte. (P and isZombie) (cteCap cte)
                                  \<or> (\<exists>zb n cp. cteCap cte = Zombie p zb n
                                       \<and> P cp \<and> (isZombie cp \<longrightarrow> capZombiePtr cp \<noteq> p))) p s)
              \<and> (fst rv \<longrightarrow> cte_wp_at' (\<lambda>cte. removeable' slot s (cteCap cte)) slot s)
              \<and> (\<forall>irq sl'. snd rv = Some irq \<longrightarrow> sl' \<noteq> slot \<longrightarrow> cteCaps_of s sl' \<noteq> Some (IRQHandlerCap irq))\<rbrace>,
   \<lbrace>\<lambda>rv s. no_orphans s \<and> invs' s \<and> sch_act_simple s\<rbrace>"
proof (induct arbitrary: P p rule: finalise_spec_induct2)
  case (1 sl exp s Q q)
  let ?P = "\<lambda>cte. (Q and isZombie) (cteCap cte)
                     \<or> (\<exists>zb n cp. cteCap cte = Zombie q zb n
                          \<and> Q cp \<and> (isZombie cp \<longrightarrow> capZombiePtr cp \<noteq> q))"
  note hyps = "1.hyps"[folded reduceZombie_def[unfolded cteDelete_def finaliseSlot_def]]
    have Q: "\<And>x y n. {x :: word32} = (\<lambda>x. y + x * 0x10) ` {0 ..< n} \<Longrightarrow> n = 1"
    apply (drule sym)
    apply (case_tac "1 < n")
     apply (frule_tac x = "y + 0 * 0x10" in eqset_imp_iff)
     apply (frule_tac x = "y + 1 * 0x10" in eqset_imp_iff)
     apply (subst(asm) imageI, simp)
      apply (erule order_less_trans[rotated], simp)
     apply (subst(asm) imageI, simp)
     apply simp
    apply (simp add: linorder_not_less)
    apply (case_tac "n < 1")
     apply simp
    apply simp
    done
  have R: "\<And>n. n \<noteq> 0 \<Longrightarrow> {0 .. n - 1} = {0 ..< n :: word32}"
    apply safe
     apply simp
     apply (erule(1) minus_one_helper5)
    apply simp
    apply (erule minus_one_helper3)
    done
  have final_IRQHandler_no_copy:
    "\<And>irq sl sl' s. \<lbrakk> isFinal (IRQHandlerCap irq) sl (cteCaps_of s); sl \<noteq> sl' \<rbrakk> \<Longrightarrow> cteCaps_of s sl' \<noteq> Some (IRQHandlerCap irq)"
    apply (clarsimp simp: isFinal_def sameObjectAs_def2 isCap_simps)
    apply fastforce
    done
  show ?case
    apply (subst finaliseSlot'.simps)
    apply (fold reduceZombie_def[unfolded cteDelete_def finaliseSlot_def])
    apply (unfold split_def)
    apply (rule hoare_pre_spec_validE)
     apply (wp | simp)+
         apply (wp make_zombie_invs' updateCap_cte_wp_at_cases hoare_vcg_disj_lift)[1]
        apply (wp hyps, assumption+)  
          apply ((wp preemptionPoint_invE preemptionPoint_invR | simp)+)[1]
         apply (rule spec_strengthen_postE[OF reduceZombie_no_orphans])
          prefer 2
          apply fastforce
         apply (rule hoare_pre_spec_validE,
                rule spec_strengthen_postE)
          apply (unfold finaliseSlot_def)[1]
           apply (rule hyps[where P="\<top>" and p=sl], (assumption | rule refl)+)
          apply clarsimp
         apply (clarsimp simp: cte_wp_at_ctes_of)
        apply (wp, simp)
        apply (wp make_zombie_invs' updateCap_ctes_of_wp updateCap_cap_to'
                  hoare_vcg_disj_lift updateCap_cte_wp_at_cases)
       apply simp
       apply (rule hoare_strengthen_post)
        apply (rule_tac Q="\<lambda>fin s. invs' s \<and> sch_act_simple s \<and> s \<turnstile>' (fst fin)
                                 \<and> (exp \<or> ex_cte_cap_to' sl s) \<and> no_orphans s
                                 \<and> cte_wp_at' (\<lambda>cte. cteCap cte = cteCap rv) sl s
                                 \<and> (q = sl \<or> exp \<or> cte_wp_at' (?P) q s)"
                   in hoare_vcg_conj_lift)
         apply (wp hoare_vcg_disj_lift finaliseCap_invs[where sl=sl])
         apply (rule finaliseCap_zombie_cap')
        apply (rule hoare_vcg_conj_lift)
         apply (rule finaliseCap_cte_refs)
        apply (rule finaliseCap_replaceable[where slot=sl])
       apply clarsimp
       apply (erule disjE[where P="F \<and> G" for F G])
        apply (clarsimp simp: capRemovable_def cte_wp_at_ctes_of)
        apply (rule conjI, clarsimp)
        apply (clarsimp simp: final_IRQHandler_no_copy)
       apply (clarsimp dest!: isCapDs)
       apply (rule conjI)
        apply (clarsimp simp: capRemovable_def)
        apply (rule conjI)
         apply (clarsimp simp: cte_wp_at_ctes_of)
         apply (rule conjI, clarsimp)
         apply (case_tac "cteCap rv",
                simp_all add: isCap_simps removeable'_def
                              fun_eq_iff[where f="cte_refs' cap" for cap]
                              fun_eq_iff[where f=tcb_cte_cases]
                              tcb_cte_cases_def
                              word_neq_0_conv[symmetric])[1]
        apply (clarsimp simp: cte_wp_at_ctes_of)
        apply (rule conjI, clarsimp)
        apply (case_tac "cteCap rv",
               simp_all add: isCap_simps removeable'_def
                             fun_eq_iff[where f="cte_refs' cap" for cap]
                             fun_eq_iff[where f=tcb_cte_cases]
                             tcb_cte_cases_def)[1]
         apply (frule Q)
         apply clarsimp
        apply (subst(asm) R)
         apply (drule valid_capAligned[OF ctes_of_valid'])
          apply fastforce
         apply (simp add: capAligned_def word_bits_def)
        apply (frule Q)
        apply clarsimp
       apply (clarsimp simp: cte_wp_at_ctes_of capRemovable_def)
       apply (subgoal_tac "final_matters' (cteCap rv) \<and> \<not> isUntypedCap (cteCap rv)")
        apply clarsimp
        apply (rule conjI)
         apply clarsimp
        apply clarsimp
       apply (case_tac "cteCap rv",
              simp_all add: isCap_simps final_matters'_def)[1]
      apply (wp isFinalCapability_inv static_imp_wp | simp | wp_once isFinal[where x=sl])+
     apply (wp getCTE_wp')
    apply (clarsimp simp: cte_wp_at_ctes_of disj_ac)
    apply (rule conjI, clarsimp simp: removeable'_def)
    apply (clarsimp simp: conj_comms)
    apply (rule conjI, erule ctes_of_valid', clarsimp)
    apply (rule conjI, clarsimp)
    apply (fastforce)
    done
qed

lemma finaliseSlot_no_orphans'':
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> (\<not> exposed \<longrightarrow> ex_cte_cap_to' slot s) \<rbrace>
     finaliseSlot slot exposed
   \<lbrace> \<lambda>rv s. no_orphans s \<and> sch_act_simple s \<and> (fst rv \<longrightarrow> cte_wp_at' (\<lambda>cte. removeable' slot s (cteCap cte)) slot s)
            \<and> (\<forall>irq sl'. snd rv = Some irq \<longrightarrow> sl' \<noteq> slot \<longrightarrow> cteCaps_of s sl' \<noteq> Some (capability.IRQHandlerCap irq)) \<rbrace>,
   \<lbrace> \<lambda>rv s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<rbrace>"
  unfolding finaliseSlot_def
  apply (rule hoare_pre, rule use_spec)
   apply (rule spec_strengthen_postE)
    apply (rule finaliseSlot_no_orphans'[where P="\<top>" and p=slot])
   apply clarsimp
  apply clarsimp
  done

lemma finaliseSlot_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> (\<not> exp \<longrightarrow> ex_cte_cap_to' slot s) \<rbrace>
    finaliseSlot slot exp
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (rule validE_valid, rule hoare_post_impErr)
    apply (rule finaliseSlot_no_orphans'')
   apply simp+
  done

lemma cteDelete_no_orphans [wp]:
  "\<lbrace> no_orphans and invs' and sch_act_simple and K ex \<rbrace>
   cteDelete ptr ex
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (rule hoare_gen_asm)
  apply (clarsimp simp: cteDelete_def whenE_def split_def)
  apply (rule hoare_pre, wp)
  apply clarsimp
  done

crunch no_orphans [wp]: cteMove "no_orphans"
(wp: crunch_wps)

lemma cteRevoke_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<rbrace>
   cteRevoke ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (rule_tac Q="\<lambda>rv s. no_orphans s \<and> invs' s \<and> sch_act_simple s"
                      in hoare_strengthen_post)
   apply (wp cteRevoke_preservation cteDelete_invs' cteDelete_sch_act_simple)
      apply auto
  done

lemma epCancelBadgedSends_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<rbrace>
   epCancelBadgedSends epptr badge
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding epCancelBadgedSends_def
  apply (rule hoare_pre)
   apply (wp hoare_drop_imps | wpc | clarsimp)+
      apply (wp filterM_preserved tcbSchedEnqueue_almost_no_orphans gts_wp'
                sts_st_tcb' hoare_drop_imps | clarsimp)+
  done

crunch no_orphans [wp]: invalidateTLBByASID "no_orphans"

lemma arch_recycleCap_no_orphans:
  "\<lbrace> \<lambda>s. cte_wp_at' (\<lambda>cte. cteCap cte = ArchObjectCap cap) slot s
         \<and> invs' s \<and> no_orphans s \<rbrace>
   ArchRetypeDecls_H.recycleCap is_final cap
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (simp add: ArchRetype_H.recycleCap_def
              split del: split_if)
  apply (rule hoare_pre)
   apply (wp mapM_x_wp' static_imp_wp | wpc | clarsimp simp: Let_def split del: split_if)+
      apply (rule_tac Q="\<lambda>rv s. no_orphans s" in hoare_post_imp)
       apply (clarsimp simp: no_orphans_def all_queued_tcb_ptrs_def
                             all_active_tcb_ptrs_def is_active_tcb_ptr_def)
      apply (wp undefined_valid | clarsimp)+
  apply (drule cte_wp_at_valid_objs_valid_cap', clarsimp+)
  apply (clarsimp simp: valid_cap'_def isCap_simps
                  split: arch_capability.splits)
  done

lemma recycleCap_no_orphans:
  "\<lbrace> \<lambda>s. cte_wp_at' (\<lambda>cte. cteCap cte = cap) slot s \<and> no_orphans s \<and> invs' s \<rbrace>
   recycleCap is_final cap
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (simp add: recycleCap_def Let_def
              cong: if_cong split del: split_if)
  apply (rule hoare_pre)
   apply (wp threadSet_no_orphans hoare_drop_imps arch_recycleCap_no_orphans[where slot=slot] | wpc
             | clarsimp simp: is_active_thread_state_def makeObject_tcb isRunning_def isRestart_def)+
  apply (auto simp: isCap_simps)
  done

lemma cteRecycle_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<rbrace>
   cteRecycle ptr
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding cteRecycle_def
  apply (rule hoare_pre)
   apply (wp weak_if_wp recycleCap_no_orphans[where slot=ptr] isFinalCapability_inv
             finaliseSlot_invs hoare_drop_imps getCTE_wp'
             | clarsimp simp: unless_def cte_wp_at_ctes_of)+
   apply (wp cteRevoke_sch_act_simple cteRevoke_invs' | clarsimp)+
  done

crunch no_orphans [wp]: handleFaultReply "no_orphans"

crunch valid_queues' [wp]: handleFaultReply "valid_queues'"

lemma doReplyTransfer_no_orphans[wp]:
  "\<lbrace>no_orphans and invs' and tcb_at' sender and tcb_at' receiver\<rbrace>
   doReplyTransfer sender receiver slot 
   \<lbrace>\<lambda>rv. no_orphans\<rbrace>"
  unfolding doReplyTransfer_def
  apply (rule hoare_pre)
   apply (wp threadSet_valid_queues' threadSet_no_orphans
             setThreadState_not_active_no_orphans sts_st_tcb'
          | wpc | clarsimp simp: is_active_thread_state_def isRunning_def
                                 isRestart_def
          | strengthen invs_valid_queues')+
              apply (rule_tac Q="\<lambda>rv. invs' and no_orphans" in hoare_post_imp)
               apply (fastforce simp: inQ_def)
              apply (wp hoare_drop_imps | clarsimp)+
  apply (clarsimp simp:invs'_def valid_state'_def valid_pspace'_def)
  done

lemma asyncIPCCancel_valid_queues' [wp]:
  "\<lbrace> \<lambda>s. valid_queues' s \<and> valid_objs' s \<rbrace>
   asyncIPCCancel t aep
   \<lbrace> \<lambda>rv s. valid_queues' s \<rbrace>"
  unfolding asyncIPCCancel_def Let_def
  apply (rule hoare_pre)
   apply (wp hoare_drop_imps | wpc | clarsimp)+
  done

crunch no_orphans [wp]: setupReplyMaster "no_orphans"

crunch valid_queues' [wp]: setupReplyMaster "valid_queues'"

lemma restart_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> tcb_at' t s \<rbrace>
   restart t
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding restart_def isBlocked_def2 
  apply (wp tcbSchedEnqueue_almost_no_orphans sts_st_tcb' | clarsimp 
         | strengthen no_orphans_strg_almost 
         | strengthen invs_valid_queues')+
  apply (rule hoare_strengthen_post, rule gts_sp')
  apply auto
  done

lemma readreg_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> tcb_at' src s \<rbrace>
     invokeTCB (tcbinvocation.ReadRegisters src susp n arch)
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding invokeTCB_def performTransfer_def
  apply (wp | clarsimp)+
  done

lemma writereg_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> tcb_at' dest s \<rbrace>
     invokeTCB (tcbinvocation.WriteRegisters dest resume values arch)
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding invokeTCB_def performTransfer_def
  apply (wp | clarsimp | rule conjI)+
  done

lemma copyreg_no_orphans:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> tcb_at' src s
         \<and> tcb_at' dest s \<and> ex_nonz_cap_to' src s \<rbrace>
     invokeTCB (tcbinvocation.CopyRegisters dest src susp resume frames ints arch)
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding invokeTCB_def performTransfer_def
  apply (wp mapM_x_wp' | clarsimp | rule conjI)+
  apply (fastforce simp: invs'_def valid_state'_def dest!: global'_no_ex_cap)
  done

lemma almost_no_orphans_no_orphans:
  "\<lbrakk> almost_no_orphans t s; \<not> is_active_tcb_ptr t s \<rbrakk> \<Longrightarrow> no_orphans s"
  by (auto simp: almost_no_orphans_def no_orphans_def all_active_tcb_ptrs_def)

lemma setPriority_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> tcb_at' tptr s \<rbrace>
   setPriority tptr prio
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding setPriority_def
  apply (wp hoare_drop_imps | clarsimp)+
      apply (wp hoare_drop_imps tcbSchedEnqueue_almost_no_orphans)
   apply (rule_tac Q="\<lambda>rv s. almost_no_orphans tptr s \<and> valid_queues' s" in hoare_post_imp)
    apply (clarsimp simp: is_active_tcb_ptr_runnable' st_tcb_at'_def
                          almost_no_orphans_no_orphans)
   apply (wp threadSet_almost_no_orphans threadSet_valid_queues' | clarsimp simp: inQ_def)+
  apply (rule_tac Q="\<lambda>rv. obj_at' (Not \<circ> tcbQueued) tptr and invs'" in hoare_post_imp)
   apply (clarsimp simp: obj_at'_def)
  apply (wp tcbSchedDequeue_not_queued | clarsimp)+
  done

lemma tc_no_orphans:
  "\<lbrace> no_orphans and invs' and sch_act_simple and tcb_at' a and ex_nonz_cap_to' a and
    case_option \<top> (valid_cap' o fst) e' and 
    K (case_option True (isCNodeCap o fst) e') and
    case_option \<top> (valid_cap' o fst) f' and
    K (case_option True (isValidVTableRoot o fst) f') and
    case_option \<top> (valid_cap') (case_option None (case_option None (Some o fst) o snd) g) and
    K (case_option True isArchObjectCap (case_option None (case_option None (Some o fst) o snd) g))
    and K (case_option True (swp is_aligned 2 o fst) g) and
    K (valid_option_prio d) \<rbrace>
      invokeTCB (tcbinvocation.ThreadControl a sl b' d e' f' g)
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (rule hoare_gen_asm)
  apply (simp add: invokeTCB_def getThreadCSpaceRoot getThreadVSpaceRoot
                   getThreadBufferSlot_def split_def)
  apply (rule hoare_walk_assmsE)
    apply (clarsimp simp: pred_conj_def option.splits[where P="\<lambda>x. x s" for s])
    apply ((wp case_option_wp threadSet_no_orphans threadSet_invs_trivial
               threadSet_cap_to' hoare_vcg_all_lift static_imp_wp | clarsimp simp: inQ_def)+)[2]
  apply (rule hoare_walk_assmsE)
    apply (clarsimp simp: pred_conj_def option.splits[where P="\<lambda>x. x s" for s])
    apply ((wp case_option_wp hoare_vcg_all_lift static_imp_wp setP_invs' | clarsimp)+)[2]
  apply (rule hoare_pre)
   apply (simp only: simp_thms cong: conj_cong
          | wp cteDelete_deletes cteDelete_invs' cteDelete_sch_act_simple
               checkCap_inv[where P="valid_cap' c" for c]
               checkCap_inv[where P=sch_act_simple]
               checkCap_inv[where P=no_orphans]
               hoare_vcg_all_lift_R hoare_vcg_all_lift
               threadSet_no_orphans hoare_vcg_const_imp_lift_R
               static_imp_wp
          | wpc | clarsimp)+
  apply (auto simp: isCap_simps dest!: isValidVTableRootD)
  done

lemma invokeTCB_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> sch_act_simple s \<and> tcb_inv_wf' tinv s \<rbrace>
   invokeTCB tinv
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (case_tac tinv, simp_all)
       apply (clarsimp simp: invokeTCB_def)
       apply (wp, clarsimp)
      apply (clarsimp simp: invokeTCB_def)
      apply (wp, clarsimp)
     apply (wp tc_no_orphans)
     apply (clarsimp split: option.splits simp: msg_align_bits elim!:is_aligned_weaken)
    apply (wp writereg_no_orphans readreg_no_orphans copyreg_no_orphans | clarsimp)+
  done

lemma invokeCNode_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> valid_cnode_inv' cinv s \<and> sch_act_simple s \<rbrace>
   invokeCNode cinv
   \<lbrace> \<lambda>rv. no_orphans \<rbrace>"
  unfolding invokeCNode_def
  apply (rule hoare_pre)
   apply (wp hoare_drop_imps | wpc | clarsimp)+
  done

lemma invokeIRQControl_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   invokeIRQControl i
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (cases i, simp_all add: invokeIRQControl_def invokeInterruptControl_def)
  apply (wp | clarsimp)+
  done

lemma invokeIRQHandler_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<rbrace>
   invokeIRQHandler i
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  apply (cases i, simp_all add: invokeIRQHandler_def)
    apply (wp | clarsimp | fastforce)+
  done

crunch no_orphans [wp]: setVMRootForFlush "no_orphans"
(wp: crunch_wps)

lemma performPageTableInvocation_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   performPageTableInvocation pti
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  apply (cases pti, simp_all add: performPageTableInvocation_def)
   apply (rule hoare_pre)
    apply (wp mapM_x_wp' | wpc | clarsimp)+
  done

lemma performPageInvocation_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   performPageInvocation pi
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  apply (simp add: performPageInvocation_def
              cong: page_invocation.case_cong)
  apply (rule hoare_pre)
   apply (wp mapM_x_wp' mapM_wp' static_imp_wp | wpc | clarsimp simp: pdeCheckIfMapped_def pteCheckIfMapped_def)+
  done

lemma performASIDControlInvocation_no_orphans [wp]:
  notes blah[simp del] = 
  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
  Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex usableUntypedRange.simps
  shows "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> valid_aci' aci s \<and> ct_active' s \<rbrace>
   performASIDControlInvocation aci
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  apply (rule hoare_name_pre_state)
  apply (clarsimp simp:valid_aci'_def cte_wp_at_ctes_of
    split:asidcontrol_invocation.splits)
  apply (rename_tac s ptr_base p cref ptr null_cte ut_cte idx)
  proof -
  fix s ptr_base p cref ptr null_cte ut_cte idx
  assume no_orphans: "no_orphans s"
    and  invs'     : "invs' s"
    and  cte       : "ctes_of s p = Some null_cte" "cteCap null_cte = capability.NullCap"
                     "ctes_of s cref = Some ut_cte" "cteCap ut_cte = capability.UntypedCap ptr_base pageBits idx"
    and  desc      : "descendants_of' cref (ctes_of s) = {}"
    and  misc      : "p \<noteq> cref" "ex_cte_cap_wp_to' (\<lambda>_. True) p s" "sch_act_simple s" "is_aligned ptr asid_low_bits"
                     "(ptr :: word32) < 2 ^ asid_bits" "ct_active' s"
  have vc:"s \<turnstile>' UntypedCap ptr_base pageBits idx"
    using cte misc invs'
    apply -
    apply (case_tac ut_cte)
    apply (rule ctes_of_valid_cap')
     apply simp
    apply fastforce
    done

   hence cover:
    "range_cover ptr_base pageBits pageBits (Suc 0)"
    apply -
    apply (rule range_cover_full)
     apply (simp add:valid_cap'_def capAligned_def)
    apply simp
    done

  have exclude: "cref \<notin> {ptr_base..ptr_base + 2 ^ pageBits - 1}"
    apply (rule descendants_range_ex_cte'[where cte = "ut_cte"])
        apply (rule empty_descendants_range_in'[OF desc])
       apply (rule if_unsafe_then_capD'[where P = "\<lambda>c. c = ut_cte"])
         apply (clarsimp simp: cte_wp_at_ctes_of cte)
        apply (simp add:invs' invs_unsafe_then_cap')
     apply (simp add:cte invs')+
    done

  show "\<lbrace>op = s\<rbrace>performASIDControlInvocation (asidcontrol_invocation.MakePool ptr_base p cref ptr) 
       \<lbrace>\<lambda>reply. no_orphans\<rbrace>"
  apply (clarsimp simp: performASIDControlInvocation_def
                  split: asidcontrol_invocation.splits)
  apply (wp static_imp_wp | clarsimp)+
    apply (rule_tac Q="\<lambda>rv s. no_orphans s" in hoare_post_imp)
     apply (clarsimp simp: no_orphans_def all_active_tcb_ptrs_def
                           is_active_tcb_ptr_def all_queued_tcb_ptrs_def)
    apply (wp | clarsimp simp:placeNewObject_def2)+
     apply (wp createObjects'_wp_subst[where c = "makeObject::asidpool"])
      apply simp
     apply (wp static_imp_wp updateFreeIndex_pspace_no_overlap'[where sz= pageBits] getSlotCap_wp | simp)+
  apply (strengthen impI[OF invs_pspace_aligned'] impI[OF invs_pspace_distinct'] impI[OF invs_valid_pspace'])
  apply (clarsimp simp:conj_comms)
     apply (wp deleteObjects_invs'[where idx = idx]
       hoare_ex_wp deleteObjects_cte_wp_at'[where idx = idx] hoare_vcg_const_imp_lift )
  using invs' misc cte exclude no_orphans cover
  apply (clarsimp simp: is_active_thread_state_def makeObject_tcb valid_aci'_def
                        cte_wp_at_ctes_of invs_pspace_aligned' invs_pspace_distinct'
                        projectKO_opt_tcb isRunning_def isRestart_def conj_comms
                        invs_valid_pspace' vc objBits_simps archObjSize_def range_cover.aligned)
  apply (intro conjI)
    apply (rule vc)
   apply (simp add:descendants_range'_def2)
   apply (rule empty_descendants_range_in'[OF desc])
  apply clarsimp
  done
qed

lemma performASIDPoolInvocation_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   performASIDPoolInvocation api
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  apply (cases api, simp_all add: performASIDPoolInvocation_def)
  apply (wp getObject_inv loadObject_default_inv | clarsimp)+
  done

lemma performPageDirectoryInvocation_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<rbrace>
   performPageDirectoryInvocation pdi
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  apply (cases pdi, simp_all add: performPageDirectoryInvocation_def)
  apply (wp | simp)+
  done

lemma arch_performInvocation_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> valid_arch_inv' i s \<and> ct_active' s \<rbrace>
   ArchRetypeDecls_H.performInvocation i
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  unfolding ArchRetype_H.performInvocation_def performARMMMUInvocation_def
  apply (cases i, simp_all add: valid_arch_inv'_def)
      apply (wp | clarsimp)+
  done

lemma setDomain_no_orphans [wp]:
  "\<lbrace>no_orphans and valid_queues and valid_queues' and cur_tcb'\<rbrace>
     setDomain tptr newdom
   \<lbrace>\<lambda>_. no_orphans\<rbrace>"
  apply (simp add: setDomain_def when_def)
  apply (wp tcbSchedEnqueue_almost_no_orphans hoare_vcg_imp_lift threadSet_almost_no_orphans
            threadSet_valid_queues'_no_state threadSet_st_tcb_at2 hoare_vcg_disj_lift
            threadSet_no_orphans
       | clarsimp simp: st_tcb_at_neg2 not_obj_at')+
   apply (auto simp: tcb_at_typ_at' st_tcb_at_neg' is_active_tcb_ptr_runnable'
                     cur_tcb'_def obj_at'_def
               dest: st_tcb_at')
  done

lemma performInvocation_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> valid_invocation' i s \<and> ct_active' s \<and> sch_act_simple s \<rbrace>
   performInvocation block call i
   \<lbrace> \<lambda>reply s. no_orphans s \<rbrace>"
  apply (simp add: performInvocation_def
              cong: invocation.case_cong)
  apply (rule hoare_pre)
   apply (wp | wpc | clarsimp)+
  apply auto
  done

lemma getThreadState_restart [wp]:
  "\<lbrace> \<lambda>s. tcb_at' thread s \<rbrace>
   getThreadState thread
   \<lbrace> \<lambda>rv s. rv = Structures_H.thread_state.Restart \<longrightarrow> st_tcb_at' isRestart thread s \<rbrace>"
  apply (rule hoare_strengthen_post)
   apply (rule gts_st_tcb')
  apply (clarsimp simp add: st_tcb_at'_def obj_at'_def isRestart_def)
  done

lemma K_bind_hoareE [wp]:
  "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>,\<lbrace>E\<rbrace> \<Longrightarrow> \<lbrace>P\<rbrace> K_bind f x \<lbrace>Q\<rbrace>,\<lbrace>E\<rbrace>"
  by simp

crunch valid_queues' [wp]: replyFromKernel "valid_queues'"

lemma handleInvocation_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<and> vs_valid_duplicates' (ksPSpace s) \<and>
         ct_active' s \<and> ksSchedulerAction s = ResumeCurrentThread \<rbrace>
   handleInvocation isCall isBlocking 
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding handleInvocation_def
  apply (rule hoare_pre)
   apply (wp syscall_valid' setThreadState_isRestart_no_orphans | wpc | clarsimp)+
          apply (rule_tac Q="\<lambda>state s. no_orphans s \<and> invs' s \<and>
                             (state = Structures_H.thread_state.Restart \<longrightarrow>
                              st_tcb_at' isRestart thread s)"
                       in hoare_post_imp)
           apply (wp | clarsimp)+
        apply (wp setThreadState_current_no_orphans sts_invs_minor'
                  ct_in_state'_set setThreadState_st_tcb
                  hoare_vcg_all_lift
                | simp add: split_def split del: split_if)+
         apply (wps setThreadState_ct')
         apply (wp sts_ksQ
                   setThreadState_current_no_orphans sts_invs_minor'
                   ct_in_state'_set setThreadState_st_tcb
                 | simp add: split_def split del: split_if)+
  apply (clarsimp)
  apply (frule(1) ct_not_ksQ)
  apply (auto simp: ct_in_state'_def st_tcb_at'_def obj_at'_def invs'_def
                    cur_tcb'_def valid_state'_def valid_idle'_def)
  done

lemma receiveAsyncIPC_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> valid_queues' s \<rbrace>
   receiveAsyncIPC thread cap
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding receiveAsyncIPC_def
  apply (wp hoare_drop_imps setThreadState_not_active_no_orphans | wpc
         | clarsimp simp: is_active_thread_state_def isRunning_def isRestart_def)+
  done

lemma receiveIPC_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<rbrace>
   receiveIPC thread cap
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding receiveIPC_def
  apply (rule hoare_pre)
   apply (wp setThreadState_not_active_no_orphans hoare_drop_imps
             hoare_vcg_all_lift sts_st_tcb' | wpc
          | clarsimp simp: is_active_thread_state_def isRunning_def isRestart_def)+
  done

crunch valid_objs' [wp]: getThreadCallerSlot "valid_objs'"

lemma deleteCallerCap_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<rbrace>
   deleteCallerCap receiver
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding deleteCallerCap_def
  apply (wp | clarsimp)+
  done

lemma remove_neg_strg: 
  "(A \<and> B) \<longrightarrow> ((x \<longrightarrow> A) \<and> (\<not> x \<longrightarrow> B))"
  by blast

lemma handleWait_no_orphans [wp]: 
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<rbrace>
   handleWait 
   \<lbrace> \<lambda>rv . no_orphans \<rbrace>"
  unfolding handleWait_def
  apply (wp hoare_drop_imps | wpc | clarsimp)+ (*takes a while*)
     apply (rule_tac Q'="\<lambda>rv s. no_orphans s \<and> invs' s" in hoare_post_imp_R)
      apply (wp, fastforce)
    apply (rule_tac Q="\<lambda>rv s. no_orphans s \<and> invs' s" in hoare_post_imp)
     apply (wp | clarsimp | fastforce)+
  done

crunch invs' [wp]: getThreadCallerSlot "invs'"

lemma handleReply_no_orphans [wp]:
  "\<lbrace>no_orphans and invs'\<rbrace> handleReply \<lbrace>\<lambda>_. no_orphans\<rbrace>"
  unfolding handleReply_def
  apply (rule hoare_pre)
   apply (wp hoare_drop_imps | wpc | clarsimp)+
     apply (wp hoare_vcg_all_lift)
      apply (rule_tac Q="\<lambda>rv s. no_orphans s \<and> invs' s \<and> tcb_at' thread s \<and>
                                valid_cap' rv s" in hoare_post_imp)
       apply (wp hoare_drop_imps | clarsimp simp: valid_cap'_def
              | clarsimp simp: invs'_def cur_tcb'_def valid_state'_def)+
  done

lemma handleYield_no_orphans [wp]:
  "\<lbrace> \<lambda>s. no_orphans s \<and> invs' s \<rbrace>
   handleYield 
   \<lbrace> \<lambda>rv . no_orphans \<rbrace>"
  unfolding handleYield_def
  apply (wp tcbSchedAppend_almost_no_orphans)
  apply auto
  done

lemma activatable_from_running':
  "ct_running' s \<Longrightarrow> ct_in_state' activatable' s"
  by (clarsimp simp: ct_in_state'_def elim!: st_tcb'_weakenE)

lemma handleEvent_no_orphans [wp]:
  "\<lbrace> \<lambda>s. invs' s \<and> vs_valid_duplicates' (ksPSpace s) \<and>
         (e \<noteq> Interrupt \<longrightarrow> ct_running' s) \<and>
         ksSchedulerAction s = ResumeCurrentThread \<and> no_orphans s \<rbrace>
   handleEvent e
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  apply (simp add: handleEvent_def handleSend_def handleCall_def
              cong: event.case_cong syscall.case_cong)
  apply (rule hoare_pre)
   apply (wp hv_inv' hoare_drop_imps | wpc | clarsimp)+
  apply (auto simp: activatable_from_running' active_from_running')
  done

(* FIXME: move? *)
lemma hoare_vcg_conj_liftE:
  "\<lbrakk> \<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>,\<lbrace>Q'\<rbrace>; \<lbrace>P'\<rbrace> f \<lbrace>R\<rbrace>,\<lbrace>E\<rbrace> \<rbrakk> \<Longrightarrow> \<lbrace>P and P'\<rbrace> f \<lbrace>\<lambda>r s. Q r s \<and> R r s\<rbrace>, \<lbrace>\<lambda>r s. Q' r s \<and> E r s\<rbrace>"
  by (fastforce simp: validE_def valid_def split: sum.splits)

theorem callKernel_no_orphans [wp]:
  "\<lbrace> \<lambda>s. invs' s \<and> vs_valid_duplicates' (ksPSpace s) \<and>
          (e \<noteq> Interrupt \<longrightarrow> ct_running' s) \<and>
          ksSchedulerAction s = ResumeCurrentThread \<and> no_orphans s \<rbrace>
   callKernel e
   \<lbrace> \<lambda>rv s. no_orphans s \<rbrace>"
  unfolding callKernel_def
  apply (wp | clarsimp)+
    apply (rule_tac Q="\<lambda>rv s. invs' s" in hoare_post_imp)
     apply (wp weak_if_wp schedule_invs' | clarsimp)+
     apply (rule_tac Q="\<lambda>_. invs'" in hoare_post_imp, clarsimp)
     apply (wp)
    apply (rule_tac Q="\<lambda>_. invs' and no_orphans" in hoare_post_imp, clarsimp)
    apply (wp | simp)+
  apply (rule_tac Q="\<lambda>y s. invs' s \<and> no_orphans s" and
                  E="\<lambda>y s. invs' s \<and> no_orphans s" in hoare_post_impErr)
    apply (wp hoare_vcg_conj_liftE | clarsimp)+
  done

end
