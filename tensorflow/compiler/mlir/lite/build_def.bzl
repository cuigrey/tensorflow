"""Build macros for TF Lite."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//tensorflow:tensorflow.bzl", "clean_dep")
load("//tensorflow/compiler/mlir/lite:special_rules.bzl", "tflite_copts_extra")

# LINT.IfChange(tflite_copts)
def tflite_copts():
    """Defines common compile time flags for TFLite libraries."""
    copts = [
        "-DFARMHASH_NO_CXX_STRING",
        "-DEIGEN_ALLOW_UNALIGNED_SCALARS",  # TODO(b/296071640): Remove when underlying bugs are fixed.
    ] + select({
        clean_dep("//tensorflow:android_arm"): [
            "-mfpu=neon",
        ],
        # copybara:uncomment_begin(google-only)
        # clean_dep("//tensorflow:chromiumos_x86_64"): [],
        # copybara:uncomment_end
        clean_dep("//tensorflow:ios_x86_64"): [
            "-msse4.1",
        ],
        clean_dep("//tensorflow:linux_x86_64"): [
            "-msse4.2",
        ],
        clean_dep("//tensorflow:linux_x86_64_no_sse"): [],
        clean_dep("//tensorflow:windows"): [
            # copybara:uncomment_begin(no MSVC flags in google)
            # "-DTFL_COMPILE_LIBRARY",
            # "-Wno-sign-compare",
            # copybara:uncomment_end_and_comment_begin
            "/DTFL_COMPILE_LIBRARY",
            "/wd4018",  # -Wno-sign-compare
            # copybara:comment_end
        ],
        "//conditions:default": [
            "-Wno-sign-compare",
        ],
    }) + select({
        clean_dep("//tensorflow:optimized"): ["-O3"],
        "//conditions:default": [],
    }) + select({
        clean_dep("//tensorflow:android"): [
            "-ffunction-sections",  # Helps trim binary size.
            "-fdata-sections",  # Helps trim binary size.
        ],
        "//conditions:default": [],
    }) + select({
        clean_dep("//tensorflow:windows"): [],
        "//conditions:default": [
            "-fno-exceptions",  # Exceptions are unused in TFLite.
        ],
    }) + select({
        clean_dep("//tensorflow/compiler/mlir/lite:tflite_with_xnnpack_explicit_false"): ["-DTFLITE_WITHOUT_XNNPACK"],
        "//conditions:default": [],
    }) + select({
        clean_dep("//tensorflow/compiler/mlir/lite:tensorflow_profiler_config"): ["-DTF_LITE_TENSORFLOW_PROFILER"],
        "//conditions:default": [],
    }) + select({
        clean_dep("//tensorflow/compiler/mlir/lite/delegates:tflite_debug_delegate"): ["-DTFLITE_DEBUG_DELEGATE"],
        "//conditions:default": [],
    }) + select({
        clean_dep("//tensorflow/compiler/mlir/lite:tflite_mmap_disabled"): ["-DTFLITE_MMAP_DISABLED"],
        "//conditions:default": [],
    })

    return copts + tflite_copts_extra()

# LINT.ThenChange(//tensorflow/lite/build_def.bzl:tflite_copts)

# LINT.IfChange(tflite_copts_warnings)
def tflite_copts_warnings():
    """Defines common warning flags used primarily by internal TFLite libraries."""

    # TODO(b/155906820): Include with `tflite_copts()` after validating clients.

    return select({
        clean_dep("//tensorflow:windows"): [
            # We run into trouble on Windows toolchains with warning flags,
            # as mentioned in the comments below on each flag.
            # We could be more aggressive in enabling supported warnings on each
            # Windows toolchain, but we compromise with keeping BUILD files simple
            # by limiting the number of config_setting's.
        ],
        "//conditions:default": [
            "-Wall",
        ],
    })

# LINT.ThenChange(//tensorflow/lite/build_def.bzl:tflite_copts_warnings)

# LINT.IfChange(tflite_cc_library_with_c_headers_test)
def tflite_cc_library_with_c_headers_test(name, hdrs, **kwargs):
    """Defines a C++ library with C-compatible header files.

    This generates a cc_library rule, but also generates
    build tests that verify that each of the 'hdrs'
    can be successfully built in a C (not C++!) compilation unit
    that directly includes only that header file.

    Args:
      name: (string) as per cc_library.
      hdrs: (list of string) as per cc_library.
      **kwargs: Additional kwargs to pass to cc_library.
    """
    native.cc_library(name = name, hdrs = hdrs, **kwargs)

    build_tests = []
    for hdr in hdrs:
        label = _label(hdr)
        basename = "%s__test_self_contained_c__%s__%s" % (name, label.package, label.name)
        compatible_with = kwargs.pop("compatible_with", [])
        native.genrule(
            name = "%s_gen" % basename,
            outs = ["%s.c" % basename],
            compatible_with = compatible_with,
            cmd = "echo '#include \"%s/%s\"' > $@" % (label.package, label.name),
            visibility = ["//visibility:private"],
            testonly = True,
        )
        kwargs.pop("visibility", None)
        kwargs.pop("deps", [])
        kwargs.pop("srcs", [])
        kwargs.pop("tags", [])
        kwargs.pop("testonly", [])
        native.cc_library(
            name = "%s_lib" % basename,
            srcs = ["%s.c" % basename],
            deps = [":" + name],
            compatible_with = compatible_with,
            copts = kwargs.pop("copts", []),
            visibility = ["//visibility:private"],
            testonly = True,
            tags = ["allow_undefined_symbols"],
            **kwargs
        )
        build_test(
            name = "%s_build_test" % basename,
            visibility = ["//visibility:private"],
            targets = ["%s_lib" % basename],
        )
        build_tests.append("%s_build_test" % basename)

    native.test_suite(
        name = name + "_self_contained_c_build_tests",
        tests = build_tests,
    )

def _label(target):
    """Return a Label <https://bazel.build/rules/lib/Label#Label> given a string.

    Args:
      target: (string) a relative or absolute build target.
    """
    if target[0:2] == "//":
        return Label(target)
    if target[0] == ":":
        return Label("//" + native.package_name() + target)
    return Label("//" + native.package_name() + ":" + target)

# LINT.ThenChange(//tensorflow/lite/build_def.bzl:tflite_cc_library_with_c_headers_test)
