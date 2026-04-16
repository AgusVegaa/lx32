; ModuleID = '/Users/axel/Pulsar/tools/lx32_backend/tests/baremetal/programs/12_run_matrix_scan.c'
source_filename = "/Users/axel/Pulsar/tools/lx32_backend/tests/baremetal/programs/12_run_matrix_scan.c"
target datalayout = "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i128:128-f64:32:64-f80:32-n8:16:32-S128"
target triple = "i386-unknown-unknown-elf"

; Function Attrs: noinline nounwind optnone
define dso_local i32 @main() #0 {
  %1 = alloca ptr, align 4
  %2 = alloca i32, align 4
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  %5 = call ptr @llvm.lx32.matrix(i32 0)
  store ptr %5, ptr %1, align 4
  %6 = call i32 @llvm.lx32.chord(i32 5)
  store i32 %6, ptr %2, align 4
  %7 = load i32, ptr %2, align 4
  store i32 0, ptr %3, align 4
  br label %8

8:                                                ; preds = %25, %0
  %9 = load i32, ptr %3, align 4
  %10 = icmp slt i32 %9, 64
  br i1 %10, label %11, label %28

11:                                               ; preds = %8
  %12 = load i32, ptr %3, align 4
  %13 = call i32 @llvm.lx32.delta(i32 %12)
  store i32 %13, ptr %4, align 4
  %14 = load ptr, ptr %1, align 4
  %15 = load i32, ptr %3, align 4
  %16 = getelementptr inbounds i16, ptr %14, i32 %15
  %17 = load i16, ptr %16, align 2
  %18 = zext i16 %17 to i32
  %19 = icmp sgt i32 %18, 2000
  br i1 %19, label %23, label %20

20:                                               ; preds = %11
  %21 = load i32, ptr %4, align 4
  %22 = icmp sgt i32 %21, 100
  br i1 %22, label %23, label %24

23:                                               ; preds = %20, %11
  call void @llvm.lx32.wait(i32 2)
  br label %24

24:                                               ; preds = %23, %20
  br label %25

25:                                               ; preds = %24
  %26 = load i32, ptr %3, align 4
  %27 = add nsw i32 %26, 1
  store i32 %27, ptr %3, align 4
  br label %8, !llvm.loop !3

28:                                               ; preds = %8
  %29 = load ptr, ptr %1, align 4
  call void @llvm.lx32.report(ptr %29)
  ret i32 0
}

; Function Attrs: nounwind memory(none)
declare ptr @llvm.lx32.matrix(i32) #1

; Function Attrs: nounwind memory(none)
declare i32 @llvm.lx32.chord(i32) #1

; Function Attrs: nounwind memory(none)
declare i32 @llvm.lx32.delta(i32) #1

; Function Attrs: nounwind
declare void @llvm.lx32.wait(i32) #2

; Function Attrs: nounwind
declare void @llvm.lx32.report(ptr) #2

attributes #0 = { noinline nounwind optnone "frame-pointer"="all" "min-legal-vector-width"="0" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="generic" "target-features"="" "tune-cpu"="generic" }
attributes #1 = { nounwind memory(none) }
attributes #2 = { nounwind }

!llvm.module.flags = !{!0, !1}
!llvm.ident = !{!2}

!0 = !{i32 1, !"NumRegisterParameters", i32 0}
!1 = !{i32 7, !"frame-pointer", i32 2}
!2 = !{!"clang version 23.0.0git (https://github.com/Axel84727/llvm-project-lx32.git 1124aa5a463f0d88df752564ca79023d0f690e60)"}
!3 = distinct !{!3, !4}
!4 = !{!"llvm.loop.mustprogress"}
