(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

chapter "Initialisation"

theory KernelInit_H
imports
  KI_Decls_H
  ArchRetype_H
  Retype_H
  Config_H
begin

fun coverOf :: "region list => region" 
where "coverOf x0 = (case x0 of
    [] =>    Region (0,0)
  | [x] =>    x
  | (x#xs) =>  
    let
        (l,h) = fromRegion x;
        (ll,hh) = fromRegion $ coverOf xs;
        ln = if l \<le> ll then l else ll;
        hn = if h \<le> hh then hh else h
    in
    Region (ln, hn)
  )"

definition syncBIFrame :: "unit kernel_init"
where "syncBIFrame \<equiv> returnOk ()"

defs minNum4kUntypedObj_def:
"minNum4kUntypedObj \<equiv> 12"

defs maxNumFreememRegions_def:
"maxNumFreememRegions \<equiv> 2"

defs getAPRegion_def:
"getAPRegion kernelFrameEnd\<equiv> (doE
   memRegions \<leftarrow> doKernelOp $ doMachineOp getMemoryRegions;
   subRegions \<leftarrow> returnOk $ (flip map) memRegions (\<lambda> x.
        let (s,e) = x in
        if s < kernelFrameEnd then (kernelFrameEnd,e) else (s,e)
      );
   returnOk $ map ptrFromPAddrRegion subRegions
odE)"

defs initFreemem_def:
"initFreemem kernelFrameEnd uiRegion\<equiv> (doE
   memRegions \<leftarrow> getAPRegion kernelFrameEnd;
   region \<leftarrow> returnOk ( fromRegion uiRegion);
   fst' \<leftarrow> returnOk ( fst \<circ> fromRegion);
   snd' \<leftarrow> returnOk ( snd \<circ> fromRegion);
   subUI \<leftarrow> returnOk ( \<lambda> r.
           if fst region \<ge> fst' r  \<and> snd region \<le> snd' r
           then [(fst' r, fst region), (snd region, snd' r)]
           else [(fst' r, snd' r)]);
   freeRegions \<leftarrow> returnOk ( concat $ map subUI memRegions);
   freeRegions' \<leftarrow> returnOk ( take maxNumFreememRegions $ freeRegions @
                      (if (length freeRegions < maxNumFreememRegions)
                       then replicate (maxNumFreememRegions - length freeRegions) (PPtr 0, PPtr 0)
                       else []));
   noInitFailure $ modify (\<lambda> st. st \<lparr> initFreeMemory := map Region freeRegions' \<rparr>)
odE)"

defs allocRegion_def:
"allocRegion bits \<equiv>
    let
        s = 1 `~shiftL~` bits;
        align = (\<lambda>  b. (((b - 1) `~shiftR~` bits) + 1) `~shiftL~` bits);
        isUsable = (\<lambda>  reg. let r = (align \<circ> fst \<circ> fromRegion) reg in
                           r \<ge> (fst $ fromRegion reg) \<and> r + s - 1 \<le> (snd $ fromRegion reg));
        isAlignedUsable = (\<lambda>  reg.
            let
                b = fst $ fromRegion reg;
                t = snd $ fromRegion reg;
                (r, q) = (align b, align t)
            in (r = b \<or> q = t) \<and> t - b \<ge> s)
    in
                          (doE
    freeMem \<leftarrow> noInitFailure $ gets initFreeMemory;
    (case isAlignedUsable `~break~` freeMem of
          (small, r#rest) \<Rightarrow>   (doE
            (b, t) \<leftarrow> returnOk ( fromRegion r);
            (result, region) \<leftarrow> returnOk ( if align b = b then (b, Region (b + s, t)) else (t - s, Region (b, t - s)));
            noInitFailure $ modify (\<lambda> st. st \<lparr> initFreeMemory := small@ [region] @rest \<rparr>);
            returnOk $ addrFromPPtr result
          odE)
        | (_, []) \<Rightarrow>  
            (case isUsable `~break~` freeMem of
                  (small, r'#rest) \<Rightarrow>   (doE
                    (b, t) \<leftarrow> returnOk ( fromRegion r');
                    result \<leftarrow> returnOk ( align b);
                    below \<leftarrow> returnOk ( if result = b then [] else [Region (b, result)]);
                    above \<leftarrow> returnOk ( if result + s = t then [] else [Region (result + s, t)]);
                    noInitFailure $ modify (\<lambda> st. st \<lparr> initFreeMemory := small@below@above@rest \<rparr>);
                    returnOk $ addrFromPPtr result
                  odE)
                | _ \<Rightarrow>   haskell_fail []
                )
        )
                          odE)"

defs initKernel_def:
"initKernel entry initFrames initOffset kernelFrames bootFrames\<equiv> (do
        wordSize \<leftarrow> return ( finiteBitSize entry);
        uiRegion \<leftarrow> return ( coverOf $ map (\<lambda> x. Region (ptrFromPAddr x, (ptrFromPAddr x) + bit (pageBits))) initFrames);
        kernelRegion \<leftarrow> return ( coverOf $ map (\<lambda> x. Region (ptrFromPAddr x, (ptrFromPAddr x) + bit (pageBits))) kernelFrames);
        kePPtr \<leftarrow> return ( fst $ fromRegion $ uiRegion);
        kfEndPAddr \<leftarrow> return ( addrFromPPtr kePPtr);
        (startPPtr,endPPtr) \<leftarrow> return $ fromRegion uiRegion;
        vptrStart \<leftarrow> return ( (VPtr (fromPAddr $ addrFromPPtr $ startPPtr )) + initOffset);
        vptrEnd \<leftarrow> return ( (VPtr (fromPAddr $ addrFromPPtr $ endPPtr )) + initOffset);
        allMemory \<leftarrow> doMachineOp getMemoryRegions;
        initPSpace $ map (\<lambda> (s, e). (ptrFromPAddr s, ptrFromPAddr e))
                         allMemory;
        mapM (\<lambda> p. reserveFrame (ptrFromPAddr p) True) $ kernelFrames @ bootFrames;
        initKernelVM;
        initCPU;
        initPlatform;
        runInit $ (doE
                initFreemem kfEndPAddr uiRegion;
                rootCNCap \<leftarrow> makeRootCNode;
                initInterruptController rootCNCap biCapIRQControl;
                ipcBufferVPtr \<leftarrow> returnOk ( vptrEnd);
                ipcBufferCap \<leftarrow> createIPCBufferFrame rootCNCap ipcBufferVPtr;
                biFrameVPtr \<leftarrow> returnOk ( vptrEnd + (1 `~shiftL~` pageBits));
                createBIFrame rootCNCap biFrameVPtr 0 1;
                createFramesOfRegion rootCNCap uiRegion True initOffset;
                itPDCap \<leftarrow> createITPDPTs rootCNCap vptrStart biFrameVPtr;
                writeITPDPTs rootCNCap itPDCap;
                itAPCap \<leftarrow> createITASIDPool rootCNCap;
                doKernelOp $ writeITASIDPool itAPCap itPDCap;
                createIdleThread;
                createInitialThread rootCNCap itPDCap ipcBufferCap entry ipcBufferVPtr biFrameVPtr;
                createUntypedObject rootCNCap (Region (0,0));
                createDeviceFrames rootCNCap;
                finaliseBIFrame;
                syncBIFrame
        odE)
od)"

defs finaliseBIFrame_def:
"finaliseBIFrame\<equiv> (doE
  cur \<leftarrow> noInitFailure $ gets $ initSlotPosCur;
  max \<leftarrow> noInitFailure $ gets $ initSlotPosMax;
  noInitFailure $ modify (\<lambda> s. s \<lparr> initBootInfo := (initBootInfo s) \<lparr>bifNullCaps := [cur  .e.  max - 1]\<rparr>\<rparr>)
odE)"

defs createInitialThread_def:
"createInitialThread rootCNCap itPDCap ipcBufferCap entry ipcBufferVPtr biFrameVPtr\<equiv> (doE
      tcbBits \<leftarrow> returnOk ( objBits (makeObject::tcb));
      tcb' \<leftarrow> allocRegion tcbBits;
      tcbPPtr \<leftarrow> returnOk ( ptrFromPAddr tcb');
      doKernelOp $ (do
         placeNewObject tcbPPtr (makeObject::tcb) 0;
         srcSlot \<leftarrow> locateSlot (capCNodePtr rootCNCap) biCapITCNode;
         destSlot \<leftarrow> getThreadCSpaceRoot tcbPPtr;
         cteInsert rootCNCap srcSlot destSlot;
         srcSlot \<leftarrow> locateSlot (capCNodePtr rootCNCap) biCapITPD;
         destSlot \<leftarrow> getThreadVSpaceRoot tcbPPtr;
         cteInsert itPDCap srcSlot destSlot;
         srcSlot \<leftarrow> locateSlot (capCNodePtr rootCNCap) biCapITIPCBuf;
         destSlot \<leftarrow> getThreadBufferSlot tcbPPtr;
         cteInsert ipcBufferCap srcSlot destSlot;
         threadSet (\<lambda> t. t\<lparr>tcbIPCBuffer := ipcBufferVPtr\<rparr>) tcbPPtr;
         activateInitialThread tcbPPtr entry biFrameVPtr;
         cap \<leftarrow> return $ ThreadCap tcbPPtr;
         slot \<leftarrow> locateSlot (capCNodePtr rootCNCap) biCapITTCB;
         insertInitCap slot cap
      od);
      returnOk ()
odE)"

defs createIdleThread_def:
"createIdleThread\<equiv> (doE
      paddr \<leftarrow> allocRegion $ objBits (makeObject ::tcb);
      tcbPPtr \<leftarrow> returnOk ( ptrFromPAddr paddr);
      doKernelOp $ (do
            placeNewObject tcbPPtr (makeObject::tcb) 0;
            modify (\<lambda> s. s \<lparr>ksIdleThread := tcbPPtr\<rparr>);
            setCurThread tcbPPtr;
            setSchedulerAction ResumeCurrentThread
      od);
      configureIdleThread tcbPPtr
odE)"

defs createUntypedObject_def:
"createUntypedObject rootCNodeCap bootMemReuseReg\<equiv> (doE
    regStart \<leftarrow> returnOk ( (fst \<circ> fromRegion));
    regStartPAddr \<leftarrow> returnOk ( (addrFromPPtr \<circ> regStart));
    regEnd \<leftarrow> returnOk ( (snd \<circ> fromRegion));
    regEndPAddr \<leftarrow> returnOk ( (addrFromPPtr \<circ> regEnd));
    slotBefore \<leftarrow> noInitFailure $ gets initSlotPosCur;
    mapME_x (\<lambda> i. provideUntypedCap rootCNodeCap i (fromIntegral pageBits) slotBefore)
             [regStartPAddr bootMemReuseReg, (regStartPAddr bootMemReuseReg + bit pageBits)  .e.  (regEndPAddr bootMemReuseReg - 1)];
    currSlot \<leftarrow> noInitFailure $ gets initSlotPosCur;
    mapME_x (\<lambda> _. (doE
             paddr \<leftarrow> allocRegion pageBits;
             provideUntypedCap rootCNodeCap paddr (fromIntegral pageBits) slotBefore
    odE)
                                                                                    )
          [(currSlot - slotBefore)  .e.  (fromIntegral minNum4kUntypedObj - 1)];
    freemem \<leftarrow> noInitFailure $ gets initFreeMemory;
    (flip mapME) (take maxNumFreememRegions freemem)
        (\<lambda> reg. (
            (\<lambda> f. mapME (f reg) [4  .e.  (finiteBitSize (undefined::machine_word)) - 2])
                (\<lambda> reg bits. (doE
                    reg' \<leftarrow> (if Not (isAligned (regStartPAddr reg) (bits + 1))
                                \<and> (regEndPAddr reg) - (regStartPAddr reg) \<ge> bit bits
                        then (doE
                            provideUntypedCap rootCNodeCap (regStartPAddr reg) (fromIntegral bits) slotBefore;
                            returnOk $ Region (regStart reg + bit bits, regEnd reg)
                        odE)
                        else returnOk reg);
                    if Not (isAligned (regEndPAddr reg') (bits + 1)) \<and> (regEndPAddr reg') - (regStartPAddr reg') \<ge> bit bits
                        then (doE
                            provideUntypedCap rootCNodeCap (regEndPAddr reg' - bit bits) (fromIntegral bits) slotBefore;
                            returnOk $ Region (regStart reg', regEnd reg' - bit bits)
                        odE)
                        else returnOk reg' 
                odE)
                                           )
        )
        );
    emptyReg \<leftarrow> returnOk ( Region (PPtr 0, PPtr 0));
    freemem' \<leftarrow> returnOk ( replicate maxNumFreememRegions emptyReg);
    slotAfter \<leftarrow> noInitFailure $ gets initSlotPosCur;
    noInitFailure $ modify (\<lambda> s. s \<lparr> initFreeMemory := freemem',
                      initBootInfo := (initBootInfo s) \<lparr>
                           bifUntypedObjCaps := [slotBefore  .e.  slotAfter - 1] \<rparr>\<rparr>)
odE)"

defs mapTaskRegions_def:
"mapTaskRegions taskMappings\<equiv> (
        haskell_fail $ [] @ show taskMappings
)"

defs allocFrame_def:
"allocFrame \<equiv> allocRegion pageBits"

defs makeRootCNode_def:
"makeRootCNode\<equiv> (doE
      slotBits \<leftarrow> returnOk ( objBits (undefined::cte));
      levelBits \<leftarrow> returnOk ( rootCNodeSize);
      frame \<leftarrow> liftME ptrFromPAddr $ allocRegion (levelBits + slotBits);
      rootCNCap \<leftarrow> doKernelOp $ createObject (fromAPIType CapTableObject) frame levelBits;
      rootCNCap \<leftarrow> returnOk $ rootCNCap \<lparr>capCNodeGuardSize := 32 - levelBits\<rparr>;
      slot \<leftarrow> doKernelOp $ locateSlot (capCNodePtr rootCNCap) biCapITCNode;
      doKernelOp $ insertInitCap slot rootCNCap;
      returnOk rootCNCap
odE)"

defs provideCap_def:
"provideCap rootCNodeCap cap\<equiv> (doE
    currSlot \<leftarrow> noInitFailure $ gets initSlotPosCur;
    maxSlot \<leftarrow> noInitFailure $ gets initSlotPosMax;
    whenE (currSlot \<ge> maxSlot) $ throwError InitFailure;
    slot \<leftarrow> doKernelOp $ locateSlot (capCNodePtr rootCNodeCap) currSlot;
    doKernelOp $ insertInitCap slot cap;
    noInitFailure $ modify (\<lambda> st. st \<lparr> initSlotPosCur := currSlot + 1 \<rparr>)
odE)"

defs provideUntypedCap_def:
"provideUntypedCap rootCNodeCap pptr magnitudeBits slotPosBefore\<equiv> (doE
    currSlot \<leftarrow> noInitFailure $ gets initSlotPosCur;
    i \<leftarrow> returnOk ( currSlot - slotPosBefore);
    untypedObjs \<leftarrow> noInitFailure $ gets (bifUntypedObjPAddrs \<circ> initBootInfo);
    haskell_assertE (length untypedObjs = fromIntegral i) [];
    untypedObjs' \<leftarrow> noInitFailure $ gets (bifUntypedObjSizeBits \<circ> initBootInfo);
    haskell_assertE (length untypedObjs' = fromIntegral i) [];
    bootInfo \<leftarrow> noInitFailure $ gets initBootInfo;
    bootInfo' \<leftarrow> returnOk ( bootInfo \<lparr> bifUntypedObjPAddrs := untypedObjs @ [pptr],
                               bifUntypedObjSizeBits := untypedObjs' @ [magnitudeBits] \<rparr>);
    noInitFailure $ modify (\<lambda> st. st \<lparr> initBootInfo := bootInfo' \<rparr>);
    provideCap rootCNodeCap $ UntypedCap_ \<lparr>
                                  capPtr= ptrFromPAddr pptr,
                                  capBlockSize= fromIntegral magnitudeBits,
                                  capFreeIndex= 0 \<rparr>
odE)"


consts
  newKSDomSchedule :: "(domain \<times> machine_word) list"
  newKSDomScheduleIdx :: nat
  newKSCurDomain :: domain
  newKSDomainTime :: machine_word
 
definition
  newKernelState :: "machine_word \<Rightarrow> kernel_state"
where
"newKernelState arg \<equiv> \<lparr>
        ksPSpace= newPSpace,
        gsUserPages= (\<lambda>x. None),
        gsCNodes= (\<lambda>x. None),
        ksDomScheduleIdx = newKSDomScheduleIdx,
        ksDomSchedule = newKSDomSchedule,
        ksCurDomain = newKSCurDomain,
        ksDomainTime = newKSDomainTime,
        ksReadyQueues= const [],
        ksCurThread= error [],
        ksIdleThread= error [],
        ksSchedulerAction= ResumeCurrentThread,
        ksInterruptState= error [],
        ksWorkUnitsCompleted= 0,
        ksArchState= fst (ArchStateData_H.newKernelState arg),
        ksMachineState= init_machine_state
	\<rparr>"

end
