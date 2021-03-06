; RUN: opt -print-mustexecute               -analyze 2>&1 < %s | FileCheck %s --check-prefix=ME
; RUN: opt -print-must-be-executed-contexts -analyze 2>&1 < %s | FileCheck %s --check-prefix=MBEC
;
;    void simple_conditional(int c) {
;      A();
;      B();
;      if (c) {
;        C();
;        D();
;      }
;      E();
;      F();
;      G();
;    }
;
; Best result:
; Start Instruction   | Visit Set
; A                   | A, B,       E, F
;    B                | A, B,       E, F
;       C             | A, B, C, D, E, F
;          D          | A, B, C, D, E, F
;             E       | A, B,       E, F
;                F    | A, B,       E, F
;                   G | A, B,       E, F, G
;
; FIXME: We miss the B -> E and backward exploration.
;
; There are no loops so print-mustexec will not do anything.
; ME-NOT: mustexec
;
define void @simple_conditional(i32 %arg) {
bb:
  call void @A()
; MBEC:      -- Explore context of:   call void @A()
; MBEC-NEXT:   [F: simple_conditional]   call void @A()
; MBEC-NEXT:   [F: simple_conditional]   call void @B()
; MBEC-NEXT:   [F: simple_conditional]   %tmp = icmp eq i32 %arg, 0
; MBEC-NEXT:   [F: simple_conditional]   br i1 %tmp, label %bb2, label %bb1
; MBEC-NOT:    call

  call void @B()
; MBEC:      -- Explore context of:   call void @B()
; MBEC-NEXT:   [F: simple_conditional]   call void @B()
; MBEC-NEXT:   [F: simple_conditional]   %tmp = icmp eq i32 %arg, 0
; MBEC-NEXT:   [F: simple_conditional]   br i1 %tmp, label %bb2, label %bb1
; MBEC-NOT:    call
; MBEC:      -- Explore context of: %tmp

  %tmp = icmp eq i32 %arg, 0
  br i1 %tmp, label %bb2, label %bb1

bb1:                                              ; preds = %bb
  call void @C()
; MBEC:      -- Explore context of:   call void @C()
; MBEC-NEXT:   [F: simple_conditional]   call void @C()
; MBEC-NEXT:   [F: simple_conditional]   call void @D()
; MBEC-NEXT:   [F: simple_conditional]   br label %bb2
; MBEC-NEXT:   [F: simple_conditional]   call void @E()
; MBEC-NEXT:   [F: simple_conditional]   call void @F()
; MBEC-NOT:    call

  call void @D()
; MBEC:      -- Explore context of:   call void @D()
; MBEC-NEXT:   [F: simple_conditional]   call void @D()
; MBEC-NEXT:   [F: simple_conditional]   br label %bb2
; MBEC-NEXT:   [F: simple_conditional]   call void @E()
; MBEC-NEXT:   [F: simple_conditional]   call void @F()
; MBEC-NOT:    call
; MBEC:      -- Explore context of: br

  br label %bb2

bb2:                                              ; preds = %bb, %bb1
  call void @E()
; MBEC:      -- Explore context of:   call void @E()
; MBEC-NEXT:   [F: simple_conditional]   call void @E()
; MBEC-NEXT:   [F: simple_conditional]   call void @F()
; MBEC-NOT:    call

  call void @F() ; might not return!
; MBEC:      -- Explore context of:   call void @F()
; MBEC-NEXT:   [F: simple_conditional]   call void @F()
; MBEC-NOT:    call

  call void @G()
; MBEC:      -- Explore context of:   call void @G()
; MBEC-NEXT:   [F: simple_conditional]   call void @G()
; MBEC-NEXT:   [F: simple_conditional]   ret void
; MBEC-NOT:    call
; MBEC:      -- Explore context of: ret

  ret void
}


;    void complex_loops_and_control(int c, int d) {
;      A();
;      while (1) {
;        B();
;        if (++c == d)
;          C();
;        if (++c == d)
;          continue;
;        D();
;        if (++c == d)
;          break;
;        do {
;          if (++c == d)
;            continue;
;          E();
;        } while (++c == d);
;        F();
;      }
;      G();
;    }
;
; Best result:
; Start Instruction    | Visit Set
; A                    | A, B
;    B                 | A, B
;       C              | A, B, C
;          D           | A, B,    D
;             E        | A, B,    D, E, F
;                F     | A, B,    D,    F
;                   G  | A, B,    D,       G
;
;
; ME: define void @complex_loops_and_control
define void @complex_loops_and_control(i32 %arg, i32 %arg1) {
bb:
  call void @A()
; ME:     call void @A()
; ME-NOT: mustexec
; ME-NEXT: br
; MBEC:      -- Explore context of:   call void @A()
; MBEC-NEXT:   [F: complex_loops_and_control]   call void @A()
; MBEC-NEXT:   [F: complex_loops_and_control]   br label %bb2
; MBEC-NEXT:   [F: complex_loops_and_control]   %.0 = phi i32 [ %arg, %bb ], [ %.0.be, %.backedge ]
; MBEC-NEXT:   [F: complex_loops_and_control]   call void @B()
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp = add nsw i32 %.0, 1
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp3 = icmp eq i32 %tmp, %arg1
; MBEC-NEXT:   [F: complex_loops_and_control]   br i1 %tmp3, label %bb4, label %bb5
; MBEC-NOT:    call
; MBEC:      -- Explore context of: br
  br label %bb2

bb2:                                              ; preds = %.backedge, %bb
  %.0 = phi i32 [ %arg, %bb ], [ %.0.be, %.backedge ]
  call void @B()
; ME: call void @B() ; (mustexec in: bb2)
; MBEC:      -- Explore context of:   call void @B()
; MBEC-NEXT:   [F: complex_loops_and_control]   call void @B()
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp = add nsw i32 %.0, 1
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp3 = icmp eq i32 %tmp, %arg1
; MBEC-NEXT:   [F: complex_loops_and_control]   br i1 %tmp3, label %bb4, label %bb5
; MBEC-NOT:    call
; MBEC:      -- Explore context of: %tmp
  %tmp = add nsw i32 %.0, 1
  %tmp3 = icmp eq i32 %tmp, %arg1
  br i1 %tmp3, label %bb4, label %bb5

bb4:                                              ; preds = %bb2
  call void @C()
; ME: call void @C()
; ME-NOT: mustexec
; ME-NEXT: br
; FIXME: Missing A and B (backward)
; MBEC:      -- Explore context of:   call void @C()
; MBEC-NEXT:   [F: complex_loops_and_control]   call void @C()
; MBEC-NEXT:   [F: complex_loops_and_control]   br label %bb5
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp6 = add nsw i32 %.0, 2
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp7 = icmp eq i32 %tmp6, %arg1
; MBEC-NEXT:   [F: complex_loops_and_control]   br i1 %tmp7, label %bb8, label %bb9
; MBEC-NOT:    call
; MBEC:      -- Explore context of: br
  br label %bb5

bb5:                                              ; preds = %bb4, %bb2
  %tmp6 = add nsw i32 %.0, 2
  %tmp7 = icmp eq i32 %tmp6, %arg1
  br i1 %tmp7, label %bb8, label %bb9

bb8:                                              ; preds = %bb5
  br label %.backedge

.backedge:                                        ; preds = %bb8, %bb22
  %.0.be = phi i32 [ %tmp6, %bb8 ], [ %.lcssa, %bb22 ]
  br label %bb2

bb9:                                              ; preds = %bb5
  call void @D()
; ME: call void @D()
; ME-NOT: mustexec
; ME-NEXT: %tmp10
; FIXME: Missing A and B (backward)
; MBEC:      -- Explore context of:   call void @D()
; MBEC-NEXT:   [F: complex_loops_and_control]   call void @D()
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp10 = add nsw i32 %.0, 3
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp11 = icmp eq i32 %tmp10, %arg1
; MBEC-NEXT:   [F: complex_loops_and_control]   br i1 %tmp11, label %bb12, label %bb13
; MBEC-NOT:    call
; MBEC:      -- Explore context of: %tmp10
  %tmp10 = add nsw i32 %.0, 3
  %tmp11 = icmp eq i32 %tmp10, %arg1
  br i1 %tmp11, label %bb12, label %bb13

bb12:                                             ; preds = %bb9
  br label %bb23

bb13:                                             ; preds = %bb9
  br label %bb14

bb14:                                             ; preds = %bb19, %bb13
  %.1 = phi i32 [ %tmp10, %bb13 ], [ %tmp20, %bb19 ]
  %tmp15 = add nsw i32 %.1, 1
  %tmp16 = icmp eq i32 %tmp15, %arg1
  br i1 %tmp16, label %bb17, label %bb18

bb17:                                             ; preds = %bb14
  br label %bb19

bb18:                                             ; preds = %bb14
  call void @E()
; ME: call void @E()
; ME-NOT: mustexec
; ME-NEXT: br
; FIXME: Missing A, B, and D (backward), as well as F
; MBEC:      -- Explore context of:   call void @E()
; MBEC-NEXT:   [F: complex_loops_and_control]   call void @E()
; MBEC-NEXT:   [F: complex_loops_and_control]   br label %bb19
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp20 = add nsw i32 %.1, 2
; MBEC-NEXT:   [F: complex_loops_and_control]   %tmp21 = icmp eq i32 %tmp20, %arg1
; MBEC-NEXT:   [F: complex_loops_and_control]   br i1 %tmp21, label %bb14, label %bb22
; MBEC-NOT:    call
; MBEC:      -- Explore context of: br
  br label %bb19

bb19:                                             ; preds = %bb18, %bb17
  %tmp20 = add nsw i32 %.1, 2
  %tmp21 = icmp eq i32 %tmp20, %arg1
  br i1 %tmp21, label %bb14, label %bb22

bb22:                                             ; preds = %bb19
  %.lcssa = phi i32 [ %tmp20, %bb19 ]
  call void @F()
; ME: call void @F()
; ME-NOT: mustexec
; ME-NEXT: br
; FIXME: Missing A, B, and D (backward)
; MBEC:      -- Explore context of:   call void @F()
; MBEC-NEXT:   [F: complex_loops_and_control]   call void @F()
; MBEC-NOT:    call
; MBEC:      -- Explore context of: br
  br label %.backedge

bb23:                                             ; preds = %bb12
  call void @G()
; ME: call void @G()
; ME-NOT: mustexec
; ME-NEXT: ret
; FIXME: Missing A, B, and D (backward)
; MBEC:      -- Explore context of:   call void @G()
; MBEC-NEXT:   [F: complex_loops_and_control]   call void @G()
; MBEC-NEXT:   [F: complex_loops_and_control]   ret void
; MBEC-NOT:    call
; MBEC:      -- Explore context of: ret
  ret void
}

declare void @A() nounwind willreturn

declare void @B() nounwind willreturn

declare void @C() nounwind willreturn

declare void @D() nounwind willreturn

declare void @E() nounwind willreturn

declare void @F() nounwind

declare void @G() nounwind willreturn
