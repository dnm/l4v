(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

(* 
	Defines the instances of pspace_storable objects.
*)

chapter "Storable Object Instances"

theory ObjectInstances_H
imports
  Structures_H
  State_H
  PSpaceStorable_H
  Config_H
begin

lemma projectKO_eq2:
  "((obj,s') \<in> fst (projectKO ko s)) = (projectKO_opt ko = Some obj \<and> s' = s)"
  by (auto simp: projectKO_def fail_def return_def split: option.splits)


-- -----------------------------------

instantiation endpoint :: pre_storable
begin

definition
  projectKO_opt_ep:
  "projectKO_opt e \<equiv> case e of KOEndpoint e \<Rightarrow> Some e | _ \<Rightarrow> None"

definition
  injectKO_ep [simp]:
  "injectKO e \<equiv> KOEndpoint e"

definition
  koType_ep [simp]:
  "koType (t::endpoint itself) \<equiv> EndpointT"

instance
  by (intro_classes,
      auto simp: projectKO_opt_ep split: kernel_object.splits arch_kernel_object.splits)

end

instantiation async_endpoint :: pre_storable
begin

definition
  projectKO_opt_aep:
  "projectKO_opt e \<equiv> case e of KOAEndpoint e \<Rightarrow> Some e | _ \<Rightarrow> None"

definition
  injectKO_aep [simp]:
  "injectKO e \<equiv> KOAEndpoint e"

definition
  koType_aep [simp]:
  "koType (t::async_endpoint itself) \<equiv> AsyncEndpointT"

instance
  by (intro_classes,
      auto simp: projectKO_opt_aep split: kernel_object.splits arch_kernel_object.splits)

end


instantiation cte :: pre_storable
begin

definition
  projectKO_opt_cte:
  "projectKO_opt e \<equiv> case e of KOCTE e \<Rightarrow> Some e | _ \<Rightarrow> None"

definition
  injectKO_cte [simp]:
  "injectKO c \<equiv> KOCTE c"

definition
  koType_cte [simp]:
  "koType (t::cte itself) \<equiv> CTET"

instance
  by (intro_classes,
      auto simp: projectKO_opt_cte split: kernel_object.splits arch_kernel_object.splits)

end


instantiation user_data :: pre_storable
begin

definition
  projectKO_opt_user_data:
  "projectKO_opt e \<equiv> case e of KOUserData \<Rightarrow> Some UserData | _ \<Rightarrow> None"

definition
  injectKO_user_data [simp]:
  "injectKO (t :: user_data) \<equiv> KOUserData"

definition
  koType_user_data [simp]:
  "koType (t::user_data itself) \<equiv> UserDataT"

instance
  by (intro_classes,
      auto simp: projectKO_opt_user_data split: kernel_object.splits arch_kernel_object.splits)

end


instantiation tcb :: pre_storable
begin

definition
  projectKO_opt_tcb:
  "projectKO_opt e \<equiv> case e of KOTCB e \<Rightarrow> Some e | _ \<Rightarrow> None"

definition
  injectKO_tcb [simp]:
  "injectKO t \<equiv> KOTCB t"

definition
  koType_tcb [simp]:
  "koType (t::tcb itself) \<equiv> TCBT"

instance
  by (intro_classes,
      auto simp: projectKO_opt_tcb split: kernel_object.splits arch_kernel_object.splits)

end


lemmas projectKO_opts_defs = 
  projectKO_opt_tcb projectKO_opt_cte projectKO_opt_aep projectKO_opt_ep projectKO_opt_user_data

lemmas injectKO_defs = 
  injectKO_tcb injectKO_cte injectKO_aep injectKO_ep injectKO_user_data

lemmas koType_defs = 
  koType_tcb koType_cte koType_aep koType_ep koType_user_data

-- -----------------------------------

instantiation endpoint :: pspace_storable
begin

#INCLUDE_HASKELL SEL4/Object/Instances.lhs instanceproofs bodies_only ONLY Endpoint

instance
  apply (intro_classes)
  apply simp
  apply (case_tac ko, auto simp: projectKO_opt_ep updateObject_default_def 
                                 in_monad projectKO_eq2 
                           split: kernel_object.splits)
  done

end


instantiation async_endpoint :: pspace_storable
begin

#INCLUDE_HASKELL SEL4/Object/Instances.lhs instanceproofs bodies_only ONLY AsyncEndpoint

instance
  apply (intro_classes)
  apply (case_tac ko, auto simp: projectKO_opt_aep updateObject_default_def 
                                 in_monad projectKO_eq2 
                           split: kernel_object.splits)
  done

end


instantiation cte :: pspace_storable
begin

#INCLUDE_HASKELL SEL4/Object/Instances.lhs instanceproofs bodies_only ONLY CTE

instance
  apply (intro_classes)
  apply (case_tac ko, auto simp: projectKO_opt_cte updateObject_cte 
                                 in_monad projectKO_eq2 typeError_def alignError_def
                           split: kernel_object.splits split_if_asm)
  done

end


instantiation user_data :: pspace_storable
begin

#INCLUDE_HASKELL SEL4/Object/Instances.lhs instanceproofs bodies_only ONLY UserData

instance
  apply (intro_classes)
  apply (case_tac ko, auto simp: projectKO_opt_user_data updateObject_default_def 
                                 in_monad projectKO_eq2 
                           split: kernel_object.splits)
  done

end


instantiation tcb :: pspace_storable
begin

#INCLUDE_HASKELL SEL4/Object/Instances.lhs instanceproofs bodies_only ONLY TCB

instance
  apply (intro_classes)
  apply (case_tac ko, auto simp: projectKO_opt_tcb updateObject_default_def 
                                 in_monad projectKO_eq2 
                           split: kernel_object.splits)
  done

end


end
