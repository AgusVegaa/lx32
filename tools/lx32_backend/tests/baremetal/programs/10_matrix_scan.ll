; ModuleID = '/Users/axel/Pulsar/tools/lx32_backend/tests/baremetal/programs/10_matrix_scan.c'
source_filename = "/Users/axel/Pulsar/tools/lx32_backend/tests/baremetal/programs/10_matrix_scan.c"
target datalayout = "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i128:128-f64:32:64-f80:32-n8:16:32-S128"
target triple = "i386-unknown-unknown-elf"

; Function Attrs: noinline nounwind optnone
define dso_local void @test_complex_scan() #0 {
  %1 = alloca ptr, align 4
  %2 = alloca i32, align 4
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  %5 = alloca i32, align 4
  %6 = alloca ptr, align 4
  %7 = alloca i32, align 4
  %8 = alloca i32, align 4
  %9 = alloca i32, align 4
  store i32 0, ptr %5, align 4
  %10 = load i32, ptr %5, align 4
  %11 = call ptr @llvm.lx32.matrix(i32 %10)
  store ptr %11, ptr %6, align 4
  store i32 5, ptr %4, align 4
  %12 = load i32, ptr %4, align 4
  %13 = call i32 @llvm.lx32.chord(i32 %12)
  store i32 %13, ptr %7, align 4
  %14 = load i32, ptr %7, align 4
  store i32 0, ptr %8, align 4
  br label %15

15:                                               ; preds = %34, %0
  %16 = load i32, ptr %8, align 4
  %17 = icmp slt i32 %16, 64
  br i1 %17, label %18, label %37

18:                                               ; preds = %15
  %19 = load i32, ptr %8, align 4
  store i32 %19, ptr %3, align 4
  %20 = load i32, ptr %3, align 4
  %21 = call i32 @llvm.lx32.delta(i32 %20)
  store i32 %21, ptr %9, align 4
  %22 = load ptr, ptr %6, align 4
  %23 = load i32, ptr %8, align 4
  %24 = getelementptr inbounds i16, ptr %22, i32 %23
  %25 = load i16, ptr %24, align 2
  %26 = zext i16 %25 to i32
  %27 = icmp sgt i32 %26, 2000
  br i1 %27, label %31, label %28

28:                                               ; preds = %18
  %29 = load i32, ptr %9, align 4
  %30 = icmp sgt i32 %29, 100
  br i1 %30, label %31, label %33

31:                                               ; preds = %28, %18
  store i32 2, ptr %2, align 4
  %32 = load i32, ptr %2, align 4
  call void @llvm.lx32.wait(i32 %32)
  br label %33

33:                                               ; preds = %31, %28
  br label %34

34:                                               ; preds = %33
  %35 = load i32, ptr %8, align 4
  %36 = add nsw i32 %35, 1
  store i32 %36, ptr %8, align 4
  br label %15, !llvm.loop !3

37:                                               ; preds = %15
  %38 = load ptr, ptr %6, align 4
  store ptr %38, ptr %1, align 4
  %39 = load ptr, ptr %1, align 4
  call void @llvm.lx32.report(ptr %39)
  ret void
}

; Function Attrs: noinline nounwind optnone
define dso_local i32 @main() #0 {
  call void @test_complex_scan() #3
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
attributes #3 = { nobuiltin "no-builtins" }

!llvm.module.flags = !{!0, !1}
!llvm.ident = !{!2}

!0 = !{i32 1, !"NumRegisterParameters", i32 0}
!1 = !{i32 7, !"frame-pointer", i32 2}
!2 = !{!"clang version 23.0.0git (https://github.com/Axel84727/llvm-project-lx32.git 1124aa5a463f0d88df752564ca79023d0f690e60)"}
!3 = distinct !{!3, !4}
!4 = !{!"llvm.loop.mustprogress"}
