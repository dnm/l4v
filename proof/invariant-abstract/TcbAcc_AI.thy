(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory TcbAcc_AI
imports CSpace_AI
begin

lemmas gts_inv[wp] = get_thread_state_inv

lemma gts_sp:
  "\<lbrace>P\<rbrace> get_thread_state t \<lbrace>\<lambda>st. st_tcb_at (\<lambda>x. st = x) t and P\<rbrace>"
  apply (simp add: pred_conj_def)
  apply (rule hoare_weaken_pre)
   apply (rule hoare_vcg_conj_lift)
    apply (rule gts_st_tcb)
   apply (rule gts_inv)
  apply simp
  done


lemma red_univ_get_wp[simp]:
  "(\<forall>(rv, s') \<in> fst (f s). s = s' \<longrightarrow> (rv, s') \<in> fst (f s'))"
  by clarsimp


lemma thread_get_inv [wp]: "\<lbrace>P\<rbrace> thread_get f t \<lbrace>\<lambda>rv. P\<rbrace>"
  by (simp add: thread_get_def | wp)+


lemma thread_get_as_user:
  "thread_get tcb_context t = as_user t get"
  apply (simp add: thread_get_def as_user_def)
  apply (rule bind_cong [OF refl])
  apply (clarsimp simp: gets_the_member)
  apply (simp add: get_def the_run_state_def set_object_def
                   put_def bind_def return_def)
  apply (drule get_tcb_SomeD)
  apply (clarsimp simp: map_upd_triv select_f_def SUP_def image_def)
  done


lemma thread_set_as_user:
  "thread_set (\<lambda>tcb. tcb \<lparr> tcb_context := f (tcb_context tcb) \<rparr>) t
    = as_user t (modify f)"
proof -
  have P: "\<And>f. det (modify f)"
    by (simp add: modify_def)
  thus ?thesis
    apply (simp add: as_user_def P thread_set_def)
    apply (clarsimp simp add: select_f_def simpler_modify_def bind_def image_def)
    done
qed


lemma ball_tcb_cap_casesI:
  "\<lbrakk> P (tcb_ctable, tcb_ctable_update, (\<lambda>_ _. \<top>));
     P (tcb_vtable, tcb_vtable_update, (\<lambda>_ _. \<top>));
     P (tcb_reply, tcb_reply_update, (\<lambda>t st c. (is_master_reply_cap c
                                                \<and> obj_ref_of c = t)
                                             \<or> (halted st \<and> (c = cap.NullCap))));
     P (tcb_caller, tcb_caller_update, (\<lambda>_ st. case st of
                                       Structures_A.BlockedOnReceive e d \<Rightarrow>
                                         (op = cap.NullCap)
                                     | _ \<Rightarrow> is_reply_cap or (op = cap.NullCap)));
     P (tcb_ipcframe, tcb_ipcframe_update, (\<lambda>_ _. is_arch_cap or (op = cap.NullCap))) \<rbrakk>
    \<Longrightarrow> \<forall>x \<in> ran tcb_cap_cases. P x"
  by (simp add: tcb_cap_cases_def)


lemma thread_set_typ_at[wp]:
  "\<lbrace>\<lambda>s. P (typ_at T p s)\<rbrace> thread_set f p' \<lbrace>\<lambda>rv s. P (typ_at T p s)\<rbrace>"
  apply (simp add: thread_set_def set_object_def)
  apply wp
  apply clarsimp
  apply (drule get_tcb_SomeD)
  apply (clarsimp simp: obj_at_def a_type_def)
  done


lemma thread_set_tcb[wp]:
  "\<lbrace>tcb_at t\<rbrace> thread_set t' f \<lbrace>\<lambda>rv. tcb_at t\<rbrace>"
  by (simp add: thread_set_typ_at [where P="\<lambda>s. s"] tcb_at_typ)


lemma thread_set_no_change_tcb_state:
  assumes x: "\<And>tcb. tcb_state  (f tcb) = tcb_state  tcb"
  shows      "\<lbrace>st_tcb_at P t\<rbrace> thread_set f t' \<lbrace>\<lambda>rv. st_tcb_at P t\<rbrace>"
  apply (simp add: thread_set_def st_tcb_at_def)
  apply wp
   apply (rule set_object_at_obj)
  apply wp
  apply (clarsimp simp: obj_at_def)
  apply (drule get_tcb_SomeD)
  apply (clarsimp simp: x)
  done


lemma thread_set_no_change_tcb_state_converse:
  assumes x: "\<And>tcb. tcb_state  (f tcb) = tcb_state  tcb"
  shows      "\<lbrace>\<lambda>s. \<not> st_tcb_at P t s\<rbrace> thread_set f t' \<lbrace>\<lambda>rv s. \<not> st_tcb_at P t s\<rbrace>"
  apply (clarsimp simp: thread_set_def st_tcb_at_def set_object_def in_monad
                        gets_the_def valid_def)
  apply (erule notE)
  apply (clarsimp simp: obj_at_def split: split_if_asm)
  apply (drule get_tcb_SomeD)
  apply (clarsimp simp: x)
  done


lemma pspace_valid_objsE:
  assumes p: "kheap s p = Some ko"
  assumes v: "valid_objs s"
  assumes Q: "\<lbrakk>kheap s p = Some ko; valid_obj p ko s\<rbrakk> \<Longrightarrow> Q"
  shows "Q"
proof -
  from p have "ko_at ko p s" by (simp add: obj_at_def)
  with v show Q by (auto elim: obj_at_valid_objsE simp: Q)
qed


lemma thread_set_split_out_set_thread_state:
  assumes f: "\<forall>tcb. (tcb_state_update (\<lambda>_. tcb_state (f undefined)) (f tcb))
                        = f tcb"
  shows "(do y \<leftarrow> thread_set f t;
             do_extended_op (set_thread_state_ext t)
          od)
      = (do thread_set (\<lambda>tcb. (f tcb) \<lparr> tcb_state := tcb_state tcb \<rparr>) t;
            set_thread_state t (tcb_state (f undefined))
         od)"
  apply (simp add: thread_set_def set_object_is_modify set_thread_state_def bind_assoc)
  apply (rule ext)
  apply (clarsimp simp: simpler_modify_def bind_def
                        gets_the_def simpler_gets_def
                        assert_opt_def fail_def return_def
                 split: option.split)
  apply (auto dest!: get_tcb_SomeD, auto simp: get_tcb_def f)
  done


schematic_lemma tcb_ipcframe_in_cases:
  "(tcb_ipcframe, ?x) \<in> ran tcb_cap_cases"
  by (fastforce simp add: ran_tcb_cap_cases)


lemma valid_ipc_buffer_cap_0[simp]:
  "valid_ipc_buffer_cap cap 0"
  by (simp add: valid_ipc_buffer_cap_def split: cap.split arch_cap.split)


lemma thread_set_valid_objs_triv:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  assumes z: "\<And>tcb. tcb_state (f tcb) = tcb_state tcb"
  assumes w: "\<And>tcb. tcb_ipc_buffer (f tcb) = tcb_ipc_buffer tcb
                         \<or> tcb_ipc_buffer (f tcb) = 0"
  assumes y: "\<And>tcb. tcb_fault_handler (f tcb) \<noteq> tcb_fault_handler tcb
                       \<longrightarrow> length (tcb_fault_handler (f tcb)) = word_bits"
  assumes a: "\<And>tcb. tcb_fault (f tcb) \<noteq> tcb_fault tcb
                       \<longrightarrow> (case tcb_fault (f tcb) of None \<Rightarrow> True
                                                   | Some f \<Rightarrow> valid_fault f)"
  shows "\<lbrace>valid_objs\<rbrace> thread_set f t \<lbrace>\<lambda>rv. valid_objs\<rbrace>"
  using bspec [OF x, OF tcb_ipcframe_in_cases]
  apply (simp add: thread_set_def)
  apply wp
   apply (rule set_object_valid_objs)
  apply wp
  apply clarsimp
  apply (drule get_tcb_SomeD)
  apply (erule (1) pspace_valid_objsE)
  apply (clarsimp simp add: valid_obj_def valid_tcb_def z
                            split_paired_Ball obj_at_def
                            a_type_def bspec_split[OF x])
  apply (rule conjI)
   apply (elim allEI)
   apply auto[1]
  apply (cut_tac tcb=y in w)
  apply (cut_tac tcb=y in y)
  apply (cut_tac tcb=y in a)
  apply auto[1]
  done


lemma thread_set_aligned [wp]:
  "\<lbrace>pspace_aligned\<rbrace> thread_set f t \<lbrace>\<lambda>rv. pspace_aligned\<rbrace>"
  apply (simp add: thread_set_def)
  apply (wp set_object_aligned)
  apply (clarsimp simp: a_type_def)
  done


lemma thread_set_distinct [wp]:
  "\<lbrace>pspace_distinct\<rbrace> thread_set f t \<lbrace>\<lambda>rv. pspace_distinct\<rbrace>"
  apply (simp add: thread_set_def)
  apply (wp set_object_distinct)
  apply clarsimp
  done


lemma thread_set_cur_tcb:
  shows "\<lbrace>\<lambda>s. cur_tcb s\<rbrace> thread_set f t \<lbrace>\<lambda>rv s. cur_tcb s\<rbrace>"
  apply (simp add: cur_tcb_def)
  apply (clarsimp simp: thread_set_def st_tcb_at_def set_object_def in_monad
                        gets_the_def valid_def)
  apply (clarsimp dest!: get_tcb_SomeD simp: obj_at_def is_tcb)
  done


lemma thread_set_iflive_trivial:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  assumes z: "\<And>tcb. tcb_state  (f tcb) = tcb_state  tcb"
  shows      "\<lbrace>if_live_then_nonz_cap\<rbrace> thread_set f t \<lbrace>\<lambda>rv. if_live_then_nonz_cap\<rbrace>"
  apply (simp add: thread_set_def)
  apply (wp set_object_iflive)
  apply (clarsimp dest!: get_tcb_SomeD)
  apply (clarsimp simp: obj_at_def get_tcb_def z
                        split_paired_Ball
                        bspec_split [OF x])
  apply (erule(1) if_live_then_nonz_capD2)
  apply simp
  done


lemma thread_set_ifunsafe_trivial:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows      "\<lbrace>if_unsafe_then_cap\<rbrace> thread_set f t \<lbrace>\<lambda>rv. if_unsafe_then_cap\<rbrace>"
  apply (simp add: thread_set_def)
  apply (wp set_object_ifunsafe)
  apply (clarsimp simp: x)
  done


lemma thread_set_zombies_trivial:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows      "\<lbrace>zombies_final\<rbrace> thread_set f t \<lbrace>\<lambda>rv. zombies_final\<rbrace>"
  apply (simp add: thread_set_def)
  apply wp
  apply (clarsimp simp: x)
  done


lemma thread_set_refs_trivial:
  assumes x: "\<And>tcb. tcb_state  (f tcb) = tcb_state  tcb"
  shows      "\<lbrace>\<lambda>s. P (state_refs_of s)\<rbrace> thread_set f t \<lbrace>\<lambda>rv s. P (state_refs_of s)\<rbrace>"
  apply (simp add: thread_set_def set_object_def)
  apply wp
  apply (clarsimp dest!: get_tcb_SomeD)
  apply (clarsimp simp: state_refs_of_def get_tcb_def x
                 elim!: rsubst[where P=P]
                intro!: ext)
  done


lemma thread_set_valid_idle_trivial:
  assumes x: "\<And>tcb. tcb_state  (f tcb) = tcb_state  tcb"
  shows      "\<lbrace>valid_idle\<rbrace> thread_set f t \<lbrace>\<lambda>_. valid_idle\<rbrace>"
  apply (simp add: thread_set_def set_object_def valid_idle_def)
  apply wp
  apply (clarsimp simp: x get_tcb_def st_tcb_at_def obj_at_def)
  done


crunch it [wp]: thread_set "\<lambda>s. P (idle_thread s)"

crunch arch [wp]: thread_set "\<lambda>s. P (arch_state s)"


lemma thread_set_arch_state [wp]:
  "\<lbrace>valid_arch_state\<rbrace> thread_set f t \<lbrace>\<lambda>_. valid_arch_state\<rbrace>"
  by (rule valid_arch_state_lift) wp


lemma thread_set_caps_of_state_trivial:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows      "\<lbrace>\<lambda>s. P (caps_of_state s)\<rbrace> thread_set f t \<lbrace>\<lambda>rv s. P (caps_of_state s)\<rbrace>"
  apply (simp add: thread_set_def set_object_def)
  apply wp
  apply (clarsimp elim!: rsubst[where P=P]
                 intro!: ext
                  dest!: get_tcb_SomeD)
  apply (subst caps_of_state_after_update)
   apply (clarsimp simp: obj_at_def get_tcb_def bspec_split [OF x])
  apply simp
  done



crunch irq_node[wp]: thread_set "\<lambda>s. P (interrupt_irq_node s)"


lemma thread_set_global_refs_triv:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows "\<lbrace>valid_global_refs\<rbrace> thread_set f t \<lbrace>\<lambda>_. valid_global_refs\<rbrace>"
  apply (rule valid_global_refs_cte_lift)
  apply (wp thread_set_caps_of_state_trivial x)
  done


lemma thread_set_valid_reply_caps_trivial:
  assumes x: "\<And>tcb. tcb_state  (f tcb) = tcb_state  tcb"
  assumes y: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows "\<lbrace>valid_reply_caps\<rbrace> thread_set f t \<lbrace>\<lambda>_. valid_reply_caps\<rbrace>"
  by (wp valid_reply_caps_st_cte_lift thread_set_caps_of_state_trivial
         thread_set_no_change_tcb_state x y)


lemma thread_set_valid_reply_masters_trivial:
  assumes y: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows "\<lbrace>valid_reply_masters\<rbrace> thread_set f t \<lbrace>\<lambda>_. valid_reply_masters\<rbrace>"
  by (wp valid_reply_masters_cte_lift thread_set_caps_of_state_trivial y)


crunch interrupt_states[wp]: thread_set "\<lambda>s. P (interrupt_states s)"


lemma thread_set_obj_at_impossible:
  "\<lbrakk> \<And>tcb. \<not> P (TCB tcb) \<rbrakk> \<Longrightarrow> \<lbrace>obj_at P p\<rbrace> thread_set f t \<lbrace>\<lambda>rv. obj_at P p\<rbrace>"
  apply (simp add: thread_set_def set_object_def)
  apply wp
  apply (clarsimp dest!: get_tcb_SomeD)
  apply (clarsimp simp: obj_at_def)
  done


lemma tcb_not_empty_table:
  "\<not> empty_table S (TCB tcb)"
  by (simp add: empty_table_def)


lemmas thread_set_arch_caps_trivial
  = valid_arch_caps_lift [OF thread_set_vs_lookup_pages thread_set_caps_of_state_trivial
                          thread_set_arch thread_set_obj_at_impossible,
                          OF _ tcb_not_empty_table]


lemmas thread_set_valid_globals[wp]
  = valid_global_objs_lift [OF thread_set_arch thread_set_arch
                                valid_ao_at_lift,
                            OF thread_set_typ_at  _ _ thread_set_obj_at_impossible,
                            simplified, OF _ _ tcb_not_empty_table,
                            OF thread_set_obj_at_impossible
                            thread_set_obj_at_impossible, simplified]


crunch v_ker_map[wp]: thread_set "valid_kernel_mappings"
  (wp: set_object_v_ker_map crunch_wps)


crunch eq_ker_map[wp]: thread_set "equal_kernel_mappings"
  (wp: set_object_equal_mappings crunch_wps ignore: set_object)


lemma thread_set_only_idle:
  "\<lbrace>only_idle and K (\<forall>tcb. tcb_state (f tcb) = tcb_state tcb \<or> \<not>idle (tcb_state (f tcb)))\<rbrace>
  thread_set f t \<lbrace>\<lambda>_. only_idle\<rbrace>"
  apply (simp add: thread_set_def set_object_def)
  apply wp
  apply (clarsimp simp: only_idle_def st_tcb_at_def obj_at_def)
  apply (drule get_tcb_SomeD)
  apply force
  done

lemma thread_set_global_pd_mappings[wp]:
  "\<lbrace>valid_global_pd_mappings\<rbrace>
      thread_set f t \<lbrace>\<lambda>rv. valid_global_pd_mappings\<rbrace>"
  apply (simp add: thread_set_def)
  apply (wp set_object_global_pd_mappings)
  apply (clarsimp simp: obj_at_def dest!: get_tcb_SomeD)
  done

lemma thread_set_pspace_in_kernel_window[wp]:
  "\<lbrace>pspace_in_kernel_window\<rbrace> thread_set f t \<lbrace>\<lambda>rv. pspace_in_kernel_window\<rbrace>"
  apply (simp add: thread_set_def)
  apply (wp set_object_pspace_in_kernel_window)
  apply (clarsimp simp: obj_at_def dest!: get_tcb_SomeD)
  done

lemma thread_set_cap_refs_in_kernel_window:
  assumes y: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows
  "\<lbrace>cap_refs_in_kernel_window\<rbrace> thread_set f t \<lbrace>\<lambda>rv. cap_refs_in_kernel_window\<rbrace>"
  apply (simp add: thread_set_def)
  apply (wp set_object_cap_refs_in_kernel_window)
  apply (clarsimp simp: obj_at_def)
  apply (clarsimp dest!: get_tcb_SomeD)
  apply (drule bspec[OF y])
  apply simp
  apply (erule sym)
  done

(* NOTE: The function "thread_set f p" updates a TCB at p using function f.
   It should not be used to change capabilities, though. *)
lemma thread_set_valid_ioc_trivial:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows "\<lbrace>valid_ioc\<rbrace> thread_set f p \<lbrace>\<lambda>_. valid_ioc\<rbrace>"
  apply (simp add: thread_set_def, wp set_object_valid_ioc_caps)
  apply clarsimp
  apply (rule conjI)
   apply clarsimp
  apply (clarsimp simp: valid_ioc_def)
  apply (drule spec, drule spec, erule impE, assumption)
  apply (cut_tac tcb=y in x)
  apply (clarsimp simp: cte_wp_at_cases get_tcb_def cap_of_def null_filter_def
                        split_def tcb_cnode_map_tcb_cap_cases
                 split: option.splits Structures_A.kernel_object.splits)
  apply (drule_tac x="(get,set,ba)" in bspec)
   apply fastforce+
  done

lemma thread_set_vms[wp]:
  "\<lbrace>valid_machine_state\<rbrace> thread_set f t \<lbrace>\<lambda>_. valid_machine_state\<rbrace>"
  apply (simp add: thread_set_def set_object_def)
  apply (wp get_object_wp)
  apply (clarsimp simp add: valid_machine_state_def in_user_frame_def)
  apply (drule_tac x=p in spec, clarsimp, rule_tac x=sz in exI)
  by (clarsimp simp: get_tcb_def obj_at_def
              split: Structures_A.kernel_object.splits)

lemma thread_set_invs_trivial:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  assumes z: "\<And>tcb. tcb_state (f tcb) = tcb_state tcb"
  assumes w: "\<And>tcb. tcb_ipc_buffer (f tcb) = tcb_ipc_buffer tcb
                       \<or> tcb_ipc_buffer (f tcb) = 0"
  assumes y: "\<And>tcb. tcb_fault_handler (f tcb) \<noteq> tcb_fault_handler tcb
                       \<longrightarrow> length (tcb_fault_handler (f tcb)) = word_bits"
  assumes a: "\<And>tcb. tcb_fault (f tcb) \<noteq> tcb_fault tcb
                       \<longrightarrow> (case tcb_fault (f tcb) of None \<Rightarrow> True
                                                   | Some f \<Rightarrow> valid_fault f)"
  shows      "\<lbrace>invs\<rbrace> thread_set f t \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def valid_pspace_def)
  apply (rule hoare_weaken_pre)
   apply (wp thread_set_valid_objs_triv
             thread_set_refs_trivial
             thread_set_iflive_trivial
             thread_set_mdb
             thread_set_ifunsafe_trivial
             thread_set_cur_tcb
             thread_set_zombies_trivial
             thread_set_valid_idle_trivial
             thread_set_global_refs_triv
             thread_set_valid_reply_caps_trivial
             thread_set_valid_reply_masters_trivial
             thread_set_valid_ioc_trivial
             valid_irq_node_typ valid_irq_handlers_lift
             thread_set_caps_of_state_trivial
             thread_set_arch_caps_trivial thread_set_only_idle
             thread_set_cap_refs_in_kernel_window
             | rule x z w y a | erule bspec_split [OF x])+
  apply (simp add: z)
  done

lemma thread_set_cte_wp_at_trivial:
  assumes x: "\<And>tcb. \<forall>(getF, v) \<in> ran tcb_cap_cases.
                  getF (f tcb) = getF tcb"
  shows "\<lbrace>\<lambda>s. Q (cte_wp_at P p s)\<rbrace> thread_set f t \<lbrace>\<lambda>rv s. Q (cte_wp_at P p s)\<rbrace>"
  by (auto simp: cte_wp_at_caps_of_state
          intro: thread_set_caps_of_state_trivial [OF x])

lemma as_user_inv:
  assumes x: "\<And>P. \<lbrace>P\<rbrace> f \<lbrace>\<lambda>x. P\<rbrace>"
  shows      "\<lbrace>P\<rbrace> as_user t f \<lbrace>\<lambda>x. P\<rbrace>"
  proof -
  have P: "\<And>a b input. (a, b) \<in> fst (f input) \<Longrightarrow> b = input"
    by (rule use_valid [OF _ x], assumption, rule refl)
  have Q: "\<And>s ps. ps (kheap s) = kheap s \<Longrightarrow> kheap_update ps s = s"
    by simp
  show ?thesis
  apply (simp add: as_user_def gets_the_def
                assert_opt_def set_object_def split_def)
  apply wp
  apply (clarsimp dest!: P)
  apply (subst Q, simp_all)
  apply (rule ext)
  apply (simp add: get_tcb_def)
  apply (case_tac "kheap s t", simp_all)
  apply (case_tac a, simp_all)
  done
qed


lemma det_query_twice:
  assumes x: "\<And>P. \<lbrace>P\<rbrace> f \<lbrace>\<lambda>x. P\<rbrace>"
  assumes y: "det f"
  shows      "do x \<leftarrow> f; y :: tcb \<leftarrow> f; g x y od
               = do x \<leftarrow> f; g x x od"
  apply (subgoal_tac "\<exists>fn. f = (\<lambda>s. ({(fn s, s)}, False))")
   apply clarsimp
   apply (rule bind_cong [OF refl])
   apply (simp add: bind_def)
  apply (rule_tac x="\<lambda>s. fst (THE x. x \<in> fst (f s))" in exI)
  apply (rule ext)
  apply (insert y, simp add: det_def)
  apply (erule_tac x=s in allE)
  apply clarsimp
  apply (rule sym)
  apply (rule state_unchanged [OF x])
  apply simp
  done


lemma user_getreg_inv[wp]:
  "\<lbrace>P\<rbrace> as_user t (get_register r) \<lbrace>\<lambda>x. P\<rbrace>"
  apply (rule as_user_inv)
  apply (simp add: get_register_def)
  done

lemma as_user_wp_thread_set_helper:
  assumes x: "
         \<lbrace>P\<rbrace> do
                tcb \<leftarrow> gets_the (get_tcb t);
                p \<leftarrow> select_f (m (tcb_context tcb));
                thread_set (\<lambda>tcb. tcb\<lparr>tcb_context := snd p\<rparr>) t
         od \<lbrace>\<lambda>rv. Q\<rbrace>"
  shows "\<lbrace>P\<rbrace> as_user t m \<lbrace>\<lambda>rv. Q\<rbrace>"
proof -
  have P: "\<And>P Q a b c f.
           \<lbrace>P\<rbrace> do x \<leftarrow> a; y \<leftarrow> b x; z \<leftarrow> c x y; return (f x y z) od \<lbrace>\<lambda>rv. Q\<rbrace>
         = \<lbrace>P\<rbrace> do x \<leftarrow> a; y \<leftarrow> b x; c x y od \<lbrace>\<lambda>rv. Q\<rbrace>"
    apply (simp add: valid_def bind_def return_def split_def)
    done
  have Q: "do
             tcb \<leftarrow> gets_the (get_tcb t);
             p \<leftarrow> select_f (m (tcb_context tcb));
             thread_set (\<lambda>tcb. tcb\<lparr>tcb_context := snd p\<rparr>) t
           od
         = do
             tcb \<leftarrow> gets_the (get_tcb t);
             p \<leftarrow> select_f (m (tcb_context tcb));
             set_object t (TCB (tcb \<lparr>tcb_context := snd p \<rparr>))
           od"
    apply (simp add: thread_set_def)
    apply (rule ext)
    apply (rule bind_apply_cong [OF refl])+
    apply (simp add: select_f_def in_monad gets_the_def gets_def)
    apply (clarsimp simp add: get_def bind_def return_def assert_opt_def)
    done
  show ?thesis
    apply (simp add: as_user_def split_def)
    apply (simp add: P x [simplified Q])
    done
qed

lemma as_user_invs[wp]: "\<lbrace>invs\<rbrace> as_user t m \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (rule as_user_wp_thread_set_helper)
  apply (wp thread_set_invs_trivial ball_tcb_cap_casesI | simp)+
  done

lemma as_user_psp_distinct[wp]:
  "\<lbrace>pspace_distinct\<rbrace> as_user t m \<lbrace>\<lambda>rv. pspace_distinct\<rbrace>"
  by (wp as_user_wp_thread_set_helper) simp


lemma as_user_psp_aligned[wp]:
  "\<lbrace>pspace_aligned\<rbrace> as_user t m \<lbrace>\<lambda>rv. pspace_aligned\<rbrace>"
  by (wp as_user_wp_thread_set_helper) simp


lemma as_user_objs [wp]:
  "\<lbrace>valid_objs\<rbrace> as_user a f \<lbrace>\<lambda>rv. valid_objs\<rbrace>"
  apply (wp as_user_wp_thread_set_helper
            thread_set_valid_objs_triv)
     apply (fastforce simp add: tcb_cap_cases_def)
  apply (wp | simp)+
  done


lemma as_user_idle[wp]:
  "\<lbrace>valid_idle\<rbrace> as_user t f \<lbrace>\<lambda>_. valid_idle\<rbrace>"
  apply (simp add: as_user_def set_object_def split_def)
  apply wp
  apply (clarsimp cong: if_cong)
  apply (clarsimp simp: obj_at_def get_tcb_def valid_idle_def st_tcb_at_def
                  split: option.splits Structures_A.kernel_object.splits)
  done


lemma as_user_reply[wp]:
  "\<lbrace>valid_reply_caps\<rbrace> as_user t f \<lbrace>\<lambda>_. valid_reply_caps\<rbrace>"
  by (wp as_user_wp_thread_set_helper thread_set_valid_reply_caps_trivial
         ball_tcb_cap_casesI | simp)+


lemma as_user_reply_masters[wp]:
  "\<lbrace>valid_reply_masters\<rbrace> as_user t f \<lbrace>\<lambda>_. valid_reply_masters\<rbrace>"
  by (wp as_user_wp_thread_set_helper thread_set_valid_reply_masters_trivial
         ball_tcb_cap_casesI | simp)+


lemma as_user_arch[wp]:
  "\<lbrace>\<lambda>s. P (arch_state s)\<rbrace> as_user t f \<lbrace>\<lambda>_ s. P (arch_state s)\<rbrace>"
  apply (simp add: as_user_def split_def)
  apply wp
  apply simp
  done


lemma as_user_irq_handlers[wp]:
  "\<lbrace>valid_irq_handlers\<rbrace> as_user t f \<lbrace>\<lambda>_. valid_irq_handlers\<rbrace>"
  apply (rule as_user_wp_thread_set_helper)
  apply (wp valid_irq_handlers_lift thread_set_caps_of_state_trivial
                ball_tcb_cap_casesI | simp)+
  done


lemma as_user_valid_arch [wp]:
  "\<lbrace>valid_arch_state\<rbrace> as_user t f \<lbrace>\<lambda>_. valid_arch_state\<rbrace>"
  by (rule valid_arch_state_lift) wp


lemma as_user_iflive[wp]:
  "\<lbrace>if_live_then_nonz_cap\<rbrace> as_user t f \<lbrace>\<lambda>_. if_live_then_nonz_cap\<rbrace>"
  by (wp as_user_wp_thread_set_helper thread_set_iflive_trivial
         ball_tcb_cap_casesI | simp)+


lemma as_user_ifunsafe[wp]:
  "\<lbrace>if_unsafe_then_cap\<rbrace> as_user t f \<lbrace>\<lambda>_. if_unsafe_then_cap\<rbrace>"
  by (wp as_user_wp_thread_set_helper thread_set_ifunsafe_trivial
         ball_tcb_cap_casesI | simp)+


lemma as_user_zombies[wp]:
  "\<lbrace>zombies_final\<rbrace> as_user t f \<lbrace>\<lambda>_. zombies_final\<rbrace>"
  by (wp as_user_wp_thread_set_helper thread_set_zombies_trivial
         ball_tcb_cap_casesI | simp)+


lemma as_user_refs_of[wp]:
  "\<lbrace>\<lambda>s. P (state_refs_of s)\<rbrace>
     as_user t m
   \<lbrace>\<lambda>rv s. P (state_refs_of s)\<rbrace>"
  apply (wp as_user_wp_thread_set_helper
            thread_set_refs_trivial | simp)+
  done


lemma as_user_caps [wp]:
  "\<lbrace>\<lambda>s. P (caps_of_state s)\<rbrace> as_user a f \<lbrace>\<lambda>_ s. P (caps_of_state s)\<rbrace>"
  apply (simp add: as_user_def split_def set_object_def)
  apply wp
  apply (clarsimp cong: if_cong)
  apply (clarsimp simp: get_tcb_def split: option.splits Structures_A.kernel_object.splits)
  apply (subst cte_wp_caps_of_lift)
   prefer 2
   apply simp
  apply (clarsimp simp: cte_wp_at_cases tcb_cap_cases_def)
  done


crunch it[wp]: as_user "\<lambda>s. P (idle_thread s)"
  (simp: crunch_simps)

crunch irq_node[wp]: as_user "\<lambda>s. P (interrupt_irq_node s)"
  (simp: crunch_simps)


lemma as_user_global_refs [wp]:
  "\<lbrace>valid_global_refs\<rbrace> as_user t f \<lbrace>\<lambda>_. valid_global_refs\<rbrace>"
  by (rule valid_global_refs_cte_lift) wp


lemma ts_cur [wp]:
  "\<lbrace>cur_tcb\<rbrace> thread_set f t \<lbrace>\<lambda>_. cur_tcb\<rbrace>"
  apply (simp add: thread_set_def set_object_def)
  apply wp
  apply (clarsimp simp: cur_tcb_def obj_at_def is_tcb)
  done


lemma as_user_ct: "\<lbrace>\<lambda>s. P (cur_thread s)\<rbrace> as_user t m \<lbrace>\<lambda>rv s. P (cur_thread s)\<rbrace>"
  apply (simp add: as_user_def split_def set_object_def)
  apply wp
  apply simp
  done


lemma as_user_cur [wp]:
  "\<lbrace>cur_tcb\<rbrace> as_user t f \<lbrace>\<lambda>_. cur_tcb\<rbrace>"
  by (wp as_user_wp_thread_set_helper) simp


lemma as_user_cte_wp_at [wp]:
  "\<lbrace>cte_wp_at P c\<rbrace> as_user p' f \<lbrace>\<lambda>rv. cte_wp_at P c\<rbrace>"
  by (wp as_user_wp_thread_set_helper
         thread_set_cte_wp_at_trivial
         ball_tcb_cap_casesI | simp)+


lemma as_user_ex_nonz_cap_to[wp]:
  "\<lbrace>ex_nonz_cap_to p\<rbrace> as_user t m \<lbrace>\<lambda>rv. ex_nonz_cap_to p\<rbrace>"
  by (wp ex_nonz_cap_to_pres)


lemma as_user_st_tcb_at [wp]:
  "\<lbrace>st_tcb_at P t\<rbrace> as_user t' m \<lbrace>\<lambda>rv. st_tcb_at P t\<rbrace>"
  by (wp as_user_wp_thread_set_helper thread_set_no_change_tcb_state
    | simp)+


lemma ct_in_state_thread_state_lift:
  assumes ct: "\<And>P. \<lbrace>\<lambda>s. P (cur_thread s)\<rbrace> f \<lbrace>\<lambda>_ s. P (cur_thread s)\<rbrace>"
  assumes st: "\<And>t. \<lbrace>st_tcb_at P t\<rbrace> f \<lbrace>\<lambda>_. st_tcb_at P t\<rbrace>"
  shows "\<lbrace>ct_in_state P\<rbrace> f \<lbrace>\<lambda>_. ct_in_state P\<rbrace>"
  apply (clarsimp simp: ct_in_state_def)
  apply (clarsimp simp: valid_def)
  apply (frule (1) use_valid [OF _ ct])
  apply (drule (1) use_valid [OF _ st], assumption)
  done

lemma as_user_ct_in_state:
  "\<lbrace>ct_in_state x\<rbrace> as_user t f \<lbrace>\<lambda>_. ct_in_state x\<rbrace>"
  by (rule ct_in_state_thread_state_lift) (wp as_user_ct)


lemma set_object_aep_at:
  "\<lbrace> aep_at p and tcb_at r \<rbrace> set_object r obj \<lbrace> \<lambda>rv. aep_at p \<rbrace>"
  apply (rule set_object_at_obj2)
  apply (clarsimp simp: is_obj_defs)
  done

lemma gts_wf[wp]: "\<lbrace>tcb_at t and invs\<rbrace> get_thread_state t \<lbrace>valid_tcb_state\<rbrace>"
  apply (simp add: get_thread_state_def thread_get_def)
  apply wp
  apply (clarsimp simp: invs_def valid_state_def valid_pspace_def
                        valid_objs_def get_tcb_def dom_def
                  split: option.splits Structures_A.kernel_object.splits)
  apply (erule allE, erule impE, blast)
  apply (clarsimp simp: valid_obj_def valid_tcb_def)
  done

lemma idle_thread_idle[wp]:
  "\<lbrace>\<lambda>s. valid_idle s \<and> t = idle_thread s\<rbrace> get_thread_state t \<lbrace>\<lambda>r s. idle r\<rbrace>"
  apply (clarsimp simp: valid_def get_thread_state_def thread_get_def bind_def return_def gets_the_def gets_def get_def assert_opt_def get_tcb_def
                        fail_def valid_idle_def st_tcb_at_def obj_at_def
                  split: option.splits Structures_A.kernel_object.splits)
  done

lemma set_thread_state_valid_objs[wp]:
 "\<lbrace>valid_objs and valid_tcb_state st and
   (\<lambda>s. (\<forall>a b. st = Structures_A.BlockedOnReceive a b \<longrightarrow>
              cte_wp_at (op = cap.NullCap) (thread, tcb_cnode_index 3) s) \<and>
        (st_tcb_at (\<lambda>st. \<not> halted st) thread s \<or> halted st \<or>
              cte_wp_at (\<lambda>c. is_master_reply_cap c \<and> obj_ref_of c = thread)
                        (thread, tcb_cnode_index 2) s))\<rbrace>
  set_thread_state thread st
  \<lbrace>\<lambda>r. valid_objs\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp set_object_valid_objs)
  apply (clarsimp simp: obj_at_def get_tcb_def is_tcb
                  split: Structures_A.kernel_object.splits option.splits)
  apply (simp add: valid_objs_def dom_def)
  apply (erule allE, erule impE, blast)
  apply (clarsimp simp: valid_obj_def valid_tcb_def
                        a_type_def tcb_cap_cases_def)
  apply (erule cte_wp_atE disjE
       | clarsimp simp: st_tcb_def2 tcb_cap_cases_def
                 dest!: get_tcb_SomeD
                 split: Structures_A.thread_state.splits)+
  done


lemma set_thread_state_aligned[wp]:
 "\<lbrace>pspace_aligned\<rbrace>
  set_thread_state thread st
  \<lbrace>\<lambda>r. pspace_aligned\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp set_object_aligned)
  apply clarsimp
  done


lemma set_thread_state_typ_at [wp]:
  "\<lbrace>\<lambda>s. P (typ_at T p s)\<rbrace> set_thread_state st p' \<lbrace>\<lambda>rv s. P (typ_at T p s)\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp, wp)
  apply clarsimp
  apply (drule get_tcb_SomeD)
  apply (clarsimp simp: obj_at_def a_type_def)
  done


lemma set_thread_state_tcb[wp]:
  "\<lbrace>tcb_at t\<rbrace> set_thread_state ts t' \<lbrace>\<lambda>rv. tcb_at t\<rbrace>"
  by (simp add: tcb_at_typ, wp)


lemma set_thread_state_cte_wp_at [wp]:
  "\<lbrace>cte_wp_at P c\<rbrace> set_thread_state st p' \<lbrace>\<lambda>rv. cte_wp_at P c\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp, wp)
  apply (clarsimp cong: if_cong)
  apply (drule get_tcb_SomeD)
  apply (auto simp: cte_wp_at_cases tcb_cap_cases_def)
  done

lemma set_object_tcb_at [wp]:
  "\<lbrace> tcb_at t' \<rbrace> set_object t (TCB x) \<lbrace>\<lambda>_. tcb_at t'\<rbrace>"
  by (rule set_object_at_obj1) (simp add: is_tcb)

lemma as_user_tcb [wp]: "\<lbrace>tcb_at t'\<rbrace> as_user t m \<lbrace>\<lambda>rv. tcb_at t'\<rbrace>"
  apply (simp add: as_user_def split_def)
  apply wp
  apply simp
  done

lemma mab_pb [simp]:
  "msg_align_bits \<le> pageBits"
  unfolding msg_align_bits pageBits_def by simp

lemma mab_wb [simp]:
  "msg_align_bits < word_bits"
  unfolding msg_align_bits word_bits_conv by simp

lemma take_min_len:
  "take (min (length xs) n) xs = take n xs"
  apply (cases "length xs \<le> n")
   apply simp
  apply (subst min.commute)
  apply (subst min.absorb1)
   apply simp
  apply simp
  done

lemma zip_take_triv2:
  "n \<ge> length as \<Longrightarrow> zip as (take n bs) = zip as bs"
  apply (induct as arbitrary: n bs)
   apply simp
  apply simp
  apply (case_tac n, simp_all)
  apply (case_tac bs, simp_all)
  done

lemma zip_take_triv:
  "n \<ge> length bs \<Longrightarrow> zip (take n as) bs = zip as bs"
  apply (induct bs arbitrary: n as, simp_all)
  apply (case_tac n, simp_all)
  apply (case_tac as, simp_all)
  done

lemma fold_fun_upd:
  "distinct keys \<Longrightarrow>
   foldl (\<lambda>s (k, v). s(k := v)) s (zip keys vals) key
   = (if key \<in> set (take (length vals) keys)
      then vals ! (the_index keys key)
      else s key)"
  apply (induct keys arbitrary: vals s)
   apply simp
  apply (case_tac vals, simp_all split del: split_if)
  apply (case_tac "key = a", simp_all split del: split_if)
   apply clarsimp
   apply (drule in_set_takeD)
   apply simp
  apply clarsimp
  done

crunch obj_at[wp]: store_word_offs "\<lambda>s. P (obj_at Q p s)"


lemma store_word_offs_in_user_frame[wp]:
  "\<lbrace>\<lambda>s. in_user_frame p s\<rbrace> store_word_offs a x w \<lbrace>\<lambda>_ s. in_user_frame p s\<rbrace>"
  unfolding in_user_frame_def
  by (wp hoare_vcg_ex_lift)


lemma as_user_in_user_frame[wp]:
  "\<lbrace>\<lambda>s. in_user_frame p s\<rbrace> as_user t m \<lbrace>\<lambda>_ s. in_user_frame p s\<rbrace>"
  unfolding in_user_frame_def
  by (wp hoare_vcg_ex_lift)


crunch obj_at[wp]: load_word_offs "\<lambda>s. P (obj_at Q p s)"


lemma load_word_offs_in_user_frame[wp]:
  "\<lbrace>\<lambda>s. in_user_frame p s\<rbrace> load_word_offs a x \<lbrace>\<lambda>_ s. in_user_frame p s\<rbrace>"
  unfolding in_user_frame_def
  by (wp hoare_vcg_ex_lift)


lemma valid_tcb_objs:
  assumes vs: "valid_objs s"
  assumes somet: "get_tcb thread s = Some y"
  shows "valid_tcb thread y s"
proof -
  from somet have inran: "kheap s thread = Some (TCB y)"
    by (clarsimp simp: get_tcb_def
                split: option.splits Structures_A.kernel_object.splits)
  with vs have "valid_obj thread (TCB y) s"
    by (fastforce simp: valid_objs_def dom_def)
  thus ?thesis by (simp add: valid_tcb_def valid_obj_def)
qed


lemma vm_sets_diff[simp]:
  "vm_read_only \<noteq> vm_read_write"
  by (simp add: vm_read_write_def vm_read_only_def)


lemmas vm_sets_diff2[simp] = not_sym[OF vm_sets_diff]


lemma get_cap_valid_ipc:
  "\<lbrace>valid_objs and obj_at (\<lambda>ko. \<exists>tcb. ko = TCB tcb \<and> tcb_ipc_buffer tcb = v) t\<rbrace>
     get_cap (t, tcb_cnode_index 4)
   \<lbrace>\<lambda>rv s. valid_ipc_buffer_cap rv v\<rbrace>"
  apply (wp get_cap_wp)
  apply clarsimp
  apply (drule(1) cte_wp_tcb_cap_valid)
  apply (clarsimp simp add: tcb_cap_valid_def obj_at_def)
  apply (simp add: valid_ipc_buffer_cap_def mask_cap_def cap_rights_update_def
                   acap_rights_update_def is_tcb
            split: cap.split_asm arch_cap.split_asm)
  done


lemma get_cap_aligned:
  "\<lbrace>valid_objs\<rbrace> get_cap slot \<lbrace>\<lambda>rv s. cap_aligned rv\<rbrace>"
  apply (rule hoare_strengthen_post, rule get_cap_valid)
  apply (clarsimp simp: valid_cap_def)
  done


lemma shiftr_eq_mask_eq:
  "a && ~~ mask b = c && ~~ mask b \<Longrightarrow> a >> b = c >> b"
  apply (rule word_eqI)
  apply (drule_tac x="n + b" in word_eqD)
  apply (case_tac "n + b < size a")
   apply (simp add: nth_shiftr word_size word_ops_nth_size)
  apply (simp add: nth_shiftr)
  apply (auto dest!: test_bit_size simp: word_size)
  done


lemma thread_get_wp:
  "\<lbrace>\<lambda>s. obj_at (\<lambda>ko. \<exists>tcb. ko = TCB tcb \<and> P (f tcb) s) ptr s\<rbrace>
    thread_get f ptr
   \<lbrace>P\<rbrace>"
  apply (clarsimp simp: valid_def obj_at_def)
  apply (frule in_inv_by_hoareD [OF thread_get_inv])
  apply (clarsimp simp: thread_get_def bind_def gets_the_def
                        assert_opt_def split_def return_def fail_def
                        gets_def get_def
                 split: option.splits
                 dest!: get_tcb_SomeD)
  done


lemma thread_get_sp:
  "\<lbrace>P\<rbrace> thread_get f ptr
   \<lbrace>\<lambda>rv. obj_at (\<lambda>ko. \<exists>tcb. ko = TCB tcb \<and> f tcb = rv) ptr and P\<rbrace>"
  apply (clarsimp simp: valid_def obj_at_def)
  apply (frule in_inv_by_hoareD [OF thread_get_inv])
  apply (clarsimp simp: thread_get_def bind_def gets_the_def
                        assert_opt_def split_def return_def fail_def
                        gets_def get_def
                 split: option.splits
                 dest!: get_tcb_SomeD)
  done


lemmas thread_get_obj_at_eq = thread_get_sp[where P=\<top>, simplified]


lemma wf_cs_0:
  "well_formed_cnode_n sz cn \<Longrightarrow> \<exists>n. n \<in> dom cn \<and> bl_to_bin n = 0"
  unfolding well_formed_cnode_n_def
  apply clarsimp
  apply (rule_tac x = "replicate sz False" in exI)
  apply (simp add: bl_to_bin_rep_False)
  done


crunch inv[wp]: lookup_ipc_buffer "I"


lemma ct_active_st_tcb_at_weaken:
  "\<lbrakk> st_tcb_at P (cur_thread s) s;
     \<And>st. P st \<Longrightarrow> active st\<rbrakk>
  \<Longrightarrow> ct_active s"
  apply (unfold ct_in_state_def)
  apply (erule st_tcb_weakenE)
  apply auto
  done


lemma ct_in_state_decomp:
  assumes x: "\<lbrace>\<lambda>s. t = (cur_thread s)\<rbrace> f \<lbrace>\<lambda>rv s. t = (cur_thread s)\<rbrace>"
  assumes y: "\<lbrace>Pre\<rbrace> f \<lbrace>\<lambda>rv. st_tcb_at Prop t\<rbrace>"
  shows      "\<lbrace>\<lambda>s. Pre s \<and> t = (cur_thread s)\<rbrace> f \<lbrace>\<lambda>rv. ct_in_state Prop\<rbrace>"
  apply (rule hoare_post_imp [where Q="\<lambda>rv s. t = cur_thread s \<and> st_tcb_at Prop t s"])
   apply (clarsimp simp add: ct_in_state_def)
  apply (rule hoare_vcg_precond_imp)
   apply (wp x y)
  apply simp
  done


lemma sts_st_tcb_at:
  "\<lbrace>\<top>\<rbrace> set_thread_state t ts \<lbrace>\<lambda>rv. st_tcb_at (\<lambda>r. r = ts) t\<rbrace>"
  by (simp add: set_thread_state_def st_tcb_at_def | wp set_object_at_obj3)+

lemma sts_st_tcb_at':
  "\<lbrace>K (P ts)\<rbrace> set_thread_state t ts \<lbrace>\<lambda>rv. st_tcb_at P t\<rbrace>"
  apply (rule hoare_assume_pre)
  apply (rule hoare_chain)
    apply (rule sts_st_tcb_at)
   apply simp
  apply (clarsimp elim!: st_tcb_weakenE)
  done


lemma sts_valid_idle [wp]:
  "\<lbrace>valid_idle and
     (\<lambda>s. t = idle_thread s \<longrightarrow> idle ts)\<rbrace>
   set_thread_state t ts
   \<lbrace>\<lambda>_. valid_idle\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp, wp)
  apply (clarsimp cong: if_cong)
  apply (clarsimp simp: valid_idle_def st_tcb_at_def obj_at_def)
  done


lemma sts_distinct [wp]:
  "\<lbrace>pspace_distinct\<rbrace> set_thread_state t st \<lbrace>\<lambda>_. pspace_distinct\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp set_object_distinct)
  apply clarsimp
  done

lemma sts_cur_tcb [wp]:
  "\<lbrace>\<lambda>s. cur_tcb s\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv s. cur_tcb s\<rbrace>"
  apply (clarsimp simp: set_thread_state_def set_object_def gets_the_def
                        valid_def in_monad)
  apply (drule get_tcb_SomeD)
  apply (frule in_dxo_pspaceD)
  apply (drule in_dxo_cur_threadD)
  apply (clarsimp simp: cur_tcb_def obj_at_def is_tcb_def)
  done

lemma sts_iflive[wp]:
  "\<lbrace>\<lambda>s. (\<not> halted st \<longrightarrow> ex_nonz_cap_to t s)
         \<and> if_live_then_nonz_cap s\<rbrace>
     set_thread_state t st
   \<lbrace>\<lambda>rv. if_live_then_nonz_cap\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp)
  apply (fastforce simp: tcb_cap_cases_def
                 split: Structures_A.thread_state.splits)
  done


lemma sts_ifunsafe[wp]:
  "\<lbrace>if_unsafe_then_cap\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. if_unsafe_then_cap\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp)
  apply (fastforce simp: tcb_cap_cases_def)
  done


lemma sts_zombies[wp]:
  "\<lbrace>zombies_final\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. zombies_final\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp)
  apply (fastforce simp: tcb_cap_cases_def)
  done


lemma sts_refs_of[wp]:
  "\<lbrace>\<lambda>s. P ((state_refs_of s) (t := tcb_st_refs_of st))\<rbrace>
    set_thread_state t st
   \<lbrace>\<lambda>rv s. P (state_refs_of s)\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp, wp)
  apply (clarsimp elim!: rsubst[where P=P]
                   simp: state_refs_of_def
                 intro!: ext)
  done


lemma set_thread_state_thread_set:
  "set_thread_state p st = (do thread_set (tcb_state_update (\<lambda>_. st)) p;
                               do_extended_op (set_thread_state_ext p)
                            od)"
  by (simp add: set_thread_state_def thread_set_def bind_assoc)


lemma set_thread_state_caps_of_state[wp]:
  "\<lbrace>\<lambda>s. P (caps_of_state s)\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv s. P (caps_of_state s)\<rbrace>"
  apply (simp add: set_thread_state_thread_set)
  apply (wp, simp, wp thread_set_caps_of_state_trivial)
  apply (rule ball_tcb_cap_casesI, simp_all)
  done


lemma sts_st_tcb_at_neq:
  "\<lbrace>st_tcb_at P t and K (t\<noteq>t')\<rbrace> set_thread_state t' st \<lbrace>\<lambda>_. st_tcb_at P t\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp, wp)
  apply (clarsimp cong: if_cong)
  apply (drule get_tcb_SomeD)
  apply (simp add: st_tcb_at_def obj_at_def)
  done


lemma sts_st_tcb_at_cases:
  "\<lbrace>\<lambda>s. ((t = t') \<longrightarrow> P ts) \<and> ((t \<noteq> t') \<longrightarrow> st_tcb_at P t' s)\<rbrace>
     set_thread_state t ts
   \<lbrace>\<lambda>rv. st_tcb_at P t'\<rbrace>"
  apply (cases "t = t'", simp_all)
   apply (wp sts_st_tcb_at')
   apply simp
  apply (wp sts_st_tcb_at_neq)
  apply simp
  done


lemma sts_reply [wp]:
  "\<lbrace>\<lambda>s. valid_reply_caps s \<and>
       (\<not> awaiting_reply st \<longrightarrow> \<not> has_reply_cap p s)\<rbrace>
   set_thread_state p st \<lbrace>\<lambda>_. valid_reply_caps\<rbrace>"
  apply (simp only: valid_reply_caps_def imp_conv_disj
                    cte_wp_at_caps_of_state has_reply_cap_def)
  apply (rule hoare_pre, wp hoare_vcg_all_lift
                            hoare_vcg_disj_lift
                            sts_st_tcb_at_cases)
  apply clarsimp
  apply (frule_tac x=x in spec)
  apply (elim disjE, simp_all)
  done


lemma sts_reply_masters [wp]:
  "\<lbrace>valid_reply_masters\<rbrace> set_thread_state p st \<lbrace>\<lambda>_. valid_reply_masters\<rbrace>"
  apply (simp add: set_thread_state_thread_set)
  apply (wp, simp, wp thread_set_valid_reply_masters_trivial)
  apply (fastforce simp: tcb_cap_cases_def)
  done


lemma set_thread_state_mdb [wp]:
  "\<lbrace>valid_mdb\<rbrace> set_thread_state p st \<lbrace>\<lambda>_. valid_mdb\<rbrace>"
  apply (simp add: set_thread_state_thread_set)
  apply (wp, simp, wp thread_set_mdb)
  apply (fastforce simp: tcb_cap_cases_def)
  done


lemma set_thread_state_global_refs [wp]:
  "\<lbrace>valid_global_refs\<rbrace> set_thread_state p st \<lbrace>\<lambda>_. valid_global_refs\<rbrace>"
  apply (simp add: set_thread_state_thread_set)
  apply (wp, simp, wp thread_set_global_refs_triv)
  apply (clarsimp simp: tcb_cap_cases_def)
  done


crunch arch [wp]: set_thread_state "\<lambda>s. P (arch_state s)"


lemma set_thread_state_valid_arch [wp]:
  "\<lbrace>valid_arch_state\<rbrace> set_thread_state p st \<lbrace>\<lambda>_. valid_arch_state\<rbrace>"
  by (rule valid_arch_state_lift) wp


lemma st_tcb_ex_cap:
  "\<lbrakk> st_tcb_at P t s; if_live_then_nonz_cap s;
      \<And>st. P st \<Longrightarrow> \<not> halted st \<rbrakk>
     \<Longrightarrow> ex_nonz_cap_to t s"
  unfolding st_tcb_at_def
  by (erule (1) if_live_then_nonz_capD, fastforce)


lemma st_tcb_cap_wp_at:
  "\<lbrakk>st_tcb_at P t s; valid_objs s;
    ref \<in> dom tcb_cap_cases;
    \<forall>cap. (st_tcb_at P t s \<and> tcb_cap_valid cap (t, ref) s) \<longrightarrow> Q cap\<rbrakk> \<Longrightarrow>
   cte_wp_at Q (t, ref) s"
  apply (clarsimp simp: cte_wp_at_cases tcb_at_def dest!: get_tcb_SomeD)
  apply (rename_tac getF setF restr)
  apply (clarsimp simp: tcb_cap_valid_def st_tcb_at_def obj_at_def)
  apply (erule(1) valid_objsE)
  apply (clarsimp simp add: valid_obj_def valid_tcb_def)
  apply (erule_tac x="(getF, setF, restr)" in ballE)
   apply fastforce+
  done


lemma st_tcb_reply_cap_valid:
  "\<And>P. \<not> P (Structures_A.Inactive) \<and> \<not> P (Structures_A.IdleThreadState) \<Longrightarrow>
   \<forall>cap. (st_tcb_at P t s \<and> tcb_cap_valid cap (t, tcb_cnode_index 2) s) \<longrightarrow>
            is_master_reply_cap cap \<and> obj_ref_of cap = t"
  by (clarsimp simp: tcb_cap_valid_def st_tcb_at_tcb_at st_tcb_def2
              split: Structures_A.thread_state.split_asm)


lemma st_tcb_caller_cap_null:
  "\<And>ep. \<forall>cap. (st_tcb_at (\<lambda>st. \<exists>b. st = Structures_A.BlockedOnReceive ep b) t s \<and>
            tcb_cap_valid cap (t, tcb_cnode_index 3) s) \<longrightarrow>
            cap = cap.NullCap"
  by (clarsimp simp: tcb_cap_valid_def st_tcb_at_tcb_at st_tcb_def2)


lemma dom_tcb_cap_cases:
  "tcb_cnode_index 0 \<in> dom tcb_cap_cases"
  "tcb_cnode_index 1 \<in> dom tcb_cap_cases"
  "tcb_cnode_index 2 \<in> dom tcb_cap_cases"
  "tcb_cnode_index 3 \<in> dom tcb_cap_cases"
  "tcb_cnode_index 4 \<in> dom tcb_cap_cases"
  by clarsimp+


lemmas st_tcb_at_reply_cap_valid =
       st_tcb_cap_wp_at [OF _ _ _ st_tcb_reply_cap_valid,
                         simplified dom_tcb_cap_cases]

lemmas st_tcb_at_caller_cap_null =
       st_tcb_cap_wp_at [OF _ _ _ st_tcb_caller_cap_null,
                         simplified dom_tcb_cap_cases]


crunch irq_node[wp]: set_thread_state "\<lambda>s. P (interrupt_irq_node s)"

crunch interrupt_states[wp]: set_thread_state "\<lambda>s. P (interrupt_states s)"

lemmas set_thread_state_valid_irq_nodes[wp]
    = valid_irq_handlers_lift [OF set_thread_state_caps_of_state
                                  set_thread_state_interrupt_states]


lemma sts_obj_at_impossible:
  "(\<And>tcb. \<not> P (TCB tcb)) \<Longrightarrow> \<lbrace>obj_at P p\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. obj_at P p\<rbrace>"
  unfolding set_thread_state_thread_set
  by (wp, simp, wp thread_set_obj_at_impossible)


lemmas sts_arch_caps[wp]
  = valid_arch_caps_lift [OF sts_vs_lookup_pages set_thread_state_caps_of_state
                             set_thread_state_arch sts_obj_at_impossible,
                          OF tcb_not_empty_table]


lemmas sts_valid_globals[wp]
  = valid_global_objs_lift [OF set_thread_state_arch set_thread_state_arch
                               valid_ao_at_lift,
                            OF set_thread_state_typ_at sts_obj_at_impossible
                               sts_obj_at_impossible sts_obj_at_impossible,
                            simplified, OF tcb_not_empty_table]


crunch v_ker_map[wp]: set_thread_state "valid_kernel_mappings"
  (wp: set_object_v_ker_map crunch_wps)


crunch eq_ker_map[wp]: set_thread_state "equal_kernel_mappings"
  (wp: set_object_equal_mappings crunch_wps ignore: set_object)


lemma sts_only_idle:
  "\<lbrace>only_idle and (\<lambda>s. idle st \<longrightarrow> t = idle_thread s)\<rbrace>
  set_thread_state t st \<lbrace>\<lambda>_. only_idle\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp, wp)
  apply (clarsimp simp: only_idle_def st_tcb_at_def obj_at_def)
  done

lemma set_thread_state_global_pd_mappings[wp]:
  "\<lbrace>valid_global_pd_mappings\<rbrace>
      set_thread_state p st \<lbrace>\<lambda>rv. valid_global_pd_mappings\<rbrace>"
  by (simp add: set_thread_state_thread_set, wp, simp, wp)

lemma set_thread_state_pspace_in_kernel_window[wp]:
  "\<lbrace>pspace_in_kernel_window\<rbrace>
      set_thread_state p st \<lbrace>\<lambda>rv. pspace_in_kernel_window\<rbrace>"
  by (simp add: set_thread_state_thread_set, wp, simp, wp)

lemma set_thread_state_cap_refs_in_kernel_window[wp]:
  "\<lbrace>cap_refs_in_kernel_window\<rbrace>
      set_thread_state p st \<lbrace>\<lambda>rv. cap_refs_in_kernel_window\<rbrace>"
  by (simp add: set_thread_state_thread_set
           | wp thread_set_cap_refs_in_kernel_window
                ball_tcb_cap_casesI)+

lemma set_thread_state_valid_ioc[wp]:
  "\<lbrace>valid_ioc\<rbrace> set_thread_state t st \<lbrace>\<lambda>_. valid_ioc\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp set_object_valid_ioc_caps)
  apply (intro impI conjI, clarsimp+)
  apply (clarsimp simp: valid_ioc_def)
  apply (drule spec, drule spec, erule impE, assumption)
  apply (clarsimp simp: get_tcb_def cap_of_def tcb_cnode_map_tcb_cap_cases
                        null_filter_def cte_wp_at_cases tcb_cap_cases_def
                 split: option.splits Structures_A.kernel_object.splits
                        split_if_asm)
  done


lemma set_thread_state_vms[wp]:
  "\<lbrace>valid_machine_state\<rbrace> set_thread_state t st \<lbrace>\<lambda>_. valid_machine_state\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp, wp)
  apply (clarsimp simp add: valid_machine_state_def in_user_frame_def)
  apply (drule_tac x=p in spec, clarsimp, rule_tac x=sz in exI)
  by (clarsimp simp: get_tcb_def obj_at_def
              split: Structures_A.kernel_object.splits)

lemma sts_invs_minor:
  "\<lbrace>st_tcb_at (\<lambda>st'. tcb_st_refs_of st' = tcb_st_refs_of st) t
     and (\<lambda>s. \<not> halted st \<longrightarrow> ex_nonz_cap_to t s)
     and (\<lambda>s. \<forall>a b. st = Structures_A.BlockedOnReceive a b \<longrightarrow>
                    cte_wp_at (op = cap.NullCap) (t, tcb_cnode_index 3) s)
     and (\<lambda>s. t \<noteq> idle_thread s)
     and (\<lambda>s. st_tcb_at (\<lambda>st. \<not> halted st) t s \<or> halted st \<or>
                    cte_wp_at (\<lambda>c. is_master_reply_cap c \<and> obj_ref_of c = t)
                              (t, tcb_cnode_index 2) s)
     and (\<lambda>s. \<forall>typ. (idle_thread s, typ) \<notin> tcb_st_refs_of st)
     and (\<lambda>s. \<not> awaiting_reply st \<longrightarrow> \<not> has_reply_cap t s)
     and K (\<not>idle st)
     and invs\<rbrace>
     set_thread_state t st
   \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def valid_pspace_def)
  apply (rule hoare_pre)
   apply (wp valid_irq_node_typ sts_only_idle | simp)+
  apply clarsimp
  apply (rule conjI)
   apply (simp add: st_tcb_at_def, erule(1) obj_at_valid_objsE)
   apply (clarsimp simp: valid_obj_def valid_tcb_def valid_tcb_state_def
                  split: Structures_A.thread_state.splits)
  apply (clarsimp elim!: rsubst[where P=sym_refs]
                 intro!: ext
                  dest!: st_tcb_at_state_refs_ofD)
  done

lemma sts_invs_minor2:
  "\<lbrace>st_tcb_at (\<lambda>st'. tcb_st_refs_of st' = tcb_st_refs_of st \<and> \<not> awaiting_reply st') t
     and invs and ex_nonz_cap_to t and (\<lambda>s. t \<noteq> idle_thread s)
     and K (\<not> awaiting_reply st \<and> \<not>idle st)
     and (\<lambda>s. \<forall>a b. st = Structures_A.BlockedOnReceive a b \<longrightarrow>
                    cte_wp_at (op = cap.NullCap) (t, tcb_cnode_index 3) s)
     and (\<lambda>s. st_tcb_at (\<lambda>st. \<not> halted st) t s \<or> halted st \<or>
                    cte_wp_at (\<lambda>c. is_master_reply_cap c \<and> obj_ref_of c = t)
                              (t, tcb_cnode_index 2) s)\<rbrace>
     set_thread_state t st
   \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def valid_pspace_def)
  apply (rule hoare_pre)
   apply (wp valid_irq_node_typ sts_only_idle)
  apply clarsimp
  apply (rule conjI)
   apply (simp add: st_tcb_at_def, erule(1) obj_at_valid_objsE)
   apply (clarsimp simp: valid_obj_def valid_tcb_def valid_tcb_state_def
                  split: Structures_A.thread_state.splits)
  apply (rule conjI)
   apply (clarsimp elim!: rsubst[where P=sym_refs]
                  intro!: ext
                   dest!: st_tcb_at_state_refs_ofD)
  apply clarsimp
  apply (drule(1) valid_reply_capsD)
  apply (clarsimp simp: st_tcb_at_def obj_at_def)
  done

lemma thread_set_valid_cap:
  shows "\<lbrace>valid_cap c\<rbrace> thread_set t p \<lbrace>\<lambda>rv. valid_cap c\<rbrace>"
  by (wp valid_cap_typ)


lemma thread_set_cte_at:
  shows "\<lbrace>cte_at c\<rbrace> thread_set t p \<lbrace>\<lambda>rv. cte_at c\<rbrace>"
  by (wp valid_cte_at_typ)


lemma set_thread_state_ko:
  "\<lbrace>ko_at obj ptr and K (\<not>is_tcb obj)\<rbrace> set_thread_state x st \<lbrace>\<lambda>rv. ko_at obj ptr\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp set_object_ko)
  apply clarsimp
  apply (drule get_tcb_SomeD)
  apply (clarsimp simp: obj_at_def is_tcb)
  done


lemma set_thread_state_valid_cap:
  "\<lbrace>valid_cap c\<rbrace> set_thread_state x st \<lbrace>\<lambda>rv. valid_cap c\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp set_object_valid_cap)
  apply clarsimp
  done


lemma set_thread_state_cte_at:
  "\<lbrace>cte_at p\<rbrace> set_thread_state x st \<lbrace>\<lambda>rv. cte_at p\<rbrace>"
  apply (simp add: set_thread_state_def)
  apply (wp, simp, wp set_object_cte_at)
  apply clarsimp
  done


lemma as_user_mdb [wp]:
  "\<lbrace>valid_mdb\<rbrace> as_user f t \<lbrace>\<lambda>_. valid_mdb\<rbrace>"
  apply (simp add: as_user_def split_def)
  apply (rule valid_mdb_lift)
    prefer 2
    apply wp
    apply simp
   prefer 2
   apply wp
   apply simp
  apply (simp add: set_object_def)
  apply wp
  apply clarsimp
  apply (subst cte_wp_caps_of_lift)
   prefer 2
   apply assumption
  apply (simp add: cte_wp_at_cases)
  apply (drule get_tcb_SomeD)
  apply (auto simp: tcb_cap_cases_def)
  done


lemma dom_mapM:
  assumes "\<And>x. empty_fail (m x)"
  shows "do_machine_op (mapM m xs) = mapM (do_machine_op \<circ> m) xs"
  by (rule submonad_mapM [OF submonad_do_machine_op submonad_do_machine_op,
                             simplified]) fact+


lemma sts_ex_nonz_cap_to[wp]:
  "\<lbrace>ex_nonz_cap_to p\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. ex_nonz_cap_to p\<rbrace>"
  by (wp ex_nonz_cap_to_pres)


lemma ct_in_state_set:
  "P st \<Longrightarrow> \<lbrace>\<lambda>s. cur_thread s = t\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. ct_in_state P \<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp add: ct_in_state_def st_tcb_at_def obj_at_def, wp)
  apply (simp add: ct_in_state_def st_tcb_at_def obj_at_def)
  done


lemma sts_ctis_neq:
  "\<lbrace>\<lambda>s. cur_thread s \<noteq> t \<and> ct_in_state P s\<rbrace> set_thread_state t st \<lbrace>\<lambda>_. ct_in_state P\<rbrace>"
  apply (simp add: ct_in_state_def set_thread_state_def set_object_def)
  apply (wp, simp add: st_tcb_at_def obj_at_def, wp)
  apply (clarsimp simp: st_tcb_at_def obj_at_def)
  done


lemma valid_running [simp]:
  "valid_tcb_state Structures_A.Running = \<top>"
  by (rule ext, simp add: valid_tcb_state_def)


lemma valid_inactive [simp]:
  "valid_tcb_state Structures_A.Inactive = \<top>"
  by (rule ext, simp add: valid_tcb_state_def)


lemma aep_queued_st_tcb_at:
  "\<And>P. \<lbrakk>ko_at (AsyncEndpoint ep) ptr s; (t, rt) \<in> aep_q_refs_of ep;
         valid_objs s; sym_refs (state_refs_of s);
         \<And>ref. P (Structures_A.BlockedOnAsyncEvent ref) \<rbrakk>
   \<Longrightarrow> st_tcb_at P t s"
  apply (case_tac ep, simp_all)
  apply (frule(1) sym_refs_ko_atD, clarsimp, erule (1) my_BallE,
         clarsimp simp: st_tcb_at_def refs_of_rev elim!: obj_at_weakenE)+
  done


lemma ep_queued_st_tcb_at:
  "\<And>P. \<lbrakk>ko_at (Endpoint ep) ptr s; (t, rt) \<in> ep_q_refs_of ep;
         valid_objs s; sym_refs (state_refs_of s);
         \<And>ref pl dim. P (Structures_A.BlockedOnSend ref pl) \<and>
  P (Structures_A.BlockedOnReceive ref dim) \<rbrakk>
    \<Longrightarrow> st_tcb_at P t s"
  apply (case_tac ep, simp_all)
  apply (frule(1) sym_refs_ko_atD, clarsimp, erule (1) my_BallE,
         clarsimp simp: st_tcb_at_def refs_of_rev elim!: obj_at_weakenE)+
  done


lemma thread_set_ct_running:
  "(\<And>tcb. tcb_state (f tcb) = tcb_state tcb) \<Longrightarrow>
  \<lbrace>ct_running\<rbrace> thread_set f t \<lbrace>\<lambda>rv. ct_running\<rbrace>"
  apply (simp add: ct_in_state_def)
  apply (rule hoare_lift_Pf [where f=cur_thread])
   apply (wp thread_set_no_change_tcb_state)
   apply simp
  apply (simp add: thread_set_def)
  apply wp
  apply simp
  done


lemmas thread_set_caps_of_state_trivial2
  = thread_set_caps_of_state_trivial [OF ball_tcb_cap_casesI]


lemmas sts_typ_ats = abs_typ_at_lifts [OF set_thread_state_typ_at]


lemma sts_tcb_ko_at:
  "\<lbrace>\<lambda>s. \<forall>v'. v = (if t = t' then v' \<lparr>tcb_state := ts\<rparr> else v')
              \<longrightarrow> ko_at (TCB v') t' s \<longrightarrow> P v\<rbrace>
      set_thread_state t ts
   \<lbrace>\<lambda>rv s. ko_at (TCB v) t' s \<longrightarrow> P v\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp, simp, wp)
  apply (clarsimp simp: obj_at_def dest!: get_tcb_SomeD)
  apply (simp add: get_tcb_def)
  done


lemma sts_tcb_cap_valid_cases:
  "\<lbrace>\<lambda>s. (t = t' \<longrightarrow> (case tcb_cap_cases ref of
                         None \<Rightarrow> True
                       | Some (getF, setF, restr) \<Rightarrow> restr t ts cap)
                   \<and> (ref = tcb_cnode_index 4 \<longrightarrow>
                        (\<forall>tcb. ko_at (TCB tcb) t' s \<longrightarrow>
                             valid_ipc_buffer_cap cap (tcb_ipc_buffer tcb)))) \<and>
        (t \<noteq> t' \<longrightarrow> tcb_cap_valid cap (t', ref) s)\<rbrace>
   set_thread_state t ts
   \<lbrace>\<lambda>_ s. tcb_cap_valid cap (t', ref) s\<rbrace>"
  apply (rule hoare_pre)
   apply (simp add: tcb_cap_valid_def tcb_at_typ)
   apply (subst imp_conv_disj)
   apply (wp hoare_vcg_disj_lift sts_st_tcb_at_cases
             hoare_vcg_const_imp_lift sts_tcb_ko_at
             hoare_vcg_all_lift)
  apply (clarsimp simp: tcb_at_st_tcb_at [THEN sym] tcb_at_typ
                        tcb_cap_valid_def
                 split: option.split)
  done


end
