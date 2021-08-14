/* Auto-generated file; do not modify! */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__gl_h_)
#error "gl.h must not be included alongside aglet.h"
#endif

#if defined(GL_GLEXT_VERSION) || defined(__gl_glext_h_)
#error "glext.h must not be included alongside aglet.h"
#endif

#define GLFW_INCLUDE_NONE

#define AGLET_ERROR_UNSPECIFIED 1
#define AGLET_ERROR_PROC_LOAD 2
#define AGLET_ERROR_GL_ERROR 3
#define AGLET_ERROR_MINIMUM_VERSION 4
#define AGLET_ERROR_MISSING_EXTENSION 5

#ifndef GLAPI
#define GLAPI extern
#endif

#ifndef APIENTRY
#if defined(_WIN32) && !defined(__CYGWIN__) && !defined(__SCITECH_SNAP__)
#define APIENTRY __stdcall
#else
#define APIENTRY
#endif
#endif

#ifndef APIENTRYP
#define APIENTRYP APIENTRY *
#endif

#include "KHR/khrplatform.h"

typedef void *(*AgletLoadProc)(const char *name);

#ifdef __APPLE__
typedef void *GLhandleARB;
#else
typedef unsigned int GLhandleARB;
#endif

#= foreach api_versions =#
GLAPI int AGLET_@{name};
#= /foreach =#

#= foreach ext_defs =#
GLAPI int AGLET_@{name};
#= /foreach =#

#= foreach type_defs =#
@{typedef}
#= /foreach =#

#= foreach enum_defs =#
#define @{name} @{value}
#= /foreach =#

#= foreach proc_defs =#
typedef @{ret_type} (APIENTRYP PFN@{name_upper}PROC)(@{params});
GLAPI PFN@{name_upper}PROC aglet_@{name};
#define @{name} aglet_@{name}
#= /foreach =#

int agletLoad(AgletLoadProc load_proc_fn);

#ifdef __cplusplus
}
#endif
