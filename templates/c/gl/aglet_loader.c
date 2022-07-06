/* Auto-generated file; do not modify! */

#include <aglet/aglet.h>

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

#= foreach api_versions =#
int AGLET_@{name} = 0;
#= /foreach =#

#= foreach extensions =#
int AGLET_@{name} = 0;
#= /foreach =#

#= foreach procs =#
PFN@{name_upper}PROC aglet_@{name} = NULL;
#= /foreach =#

static int _load_versions(AgletLoadProc load_proc) {
    GLenum(*local_glGetError)() = (GLenum(*)()) load_proc("glGetError");
    if (local_glGetError == NULL) {
        return AGLET_ERROR_PROC_LOAD;
    }

    #ifdef GL_MAJOR_VERSION
    void (*local_glGetIntegerv)(GLenum, GLint*) = (void(*)(GLenum, GLint*)) load_proc("glGetIntegerv");

    if (local_glGetIntegerv == NULL) {
        return AGLET_ERROR_PROC_LOAD;
    }

    int glErr = local_glGetError();
    if (glErr == GL_NO_ERROR) {
        int ver_major;
        int ver_minor;

        local_glGetIntegerv(GL_MAJOR_VERSION, &ver_major);
        if (local_glGetError() != GL_NO_ERROR) {
            return AGLET_ERROR_GL_ERROR;
        }

        local_glGetIntegerv(GL_MINOR_VERSION, &ver_minor);
        if (local_glGetError() != GL_NO_ERROR) {
            return AGLET_ERROR_GL_ERROR;
        }

        #= foreach api_versions =#
        AGLET_@{name} = (ver_major > @{major} || (ver_major == @{major} && ver_minor >= @{minor})) ? 1 : 0;
        #= /foreach =#

        return 0;
    } else if (glErr != GL_INVALID_ENUM) {
        return AGLET_ERROR_GL_ERROR;
    }
    #endif

    // fallback section

    const GLubyte *(*local_glGetString)(GLenum name) = (const GLubyte*(*)(GLenum)) load_proc("glGetString");
    if (local_glGetString == NULL) {
        return AGLET_ERROR_PROC_LOAD;
    }

    const char *ver_str = (const char *) local_glGetString(GL_VERSION);
    if (local_glGetError() != GL_NO_ERROR || ver_str == NULL) {
        return AGLET_ERROR_GL_ERROR;
    }

    char major_str[4];
    char minor_str[4];
    char *dot_off_1 = strchr(ver_str, '.');
    if (dot_off_1 == NULL || strlen(dot_off_1) < 2) {
        return AGLET_ERROR_UNSPECIFIED;
    }
    size_t major_len = (size_t) (dot_off_1 - ver_str);

    char *dot_off_2 = NULL;
    for (size_t i = 2; i < strlen(dot_off_1) - 1; i++) {
        if (dot_off_1[i] == '.' || dot_off_1[i] == ' ') {
            dot_off_2 = dot_off_1 + i;
            break;
        }
    }

    if (dot_off_2 == NULL) {
        return AGLET_ERROR_UNSPECIFIED;
    }

    size_t minor_len = (size_t) (dot_off_2 - dot_off_1 - 1);
    if (minor_len > sizeof(minor_str) - 1) {
        return AGLET_ERROR_UNSPECIFIED;
    }

    memcpy(major_str, ver_str, major_len);
    major_str[major_len] = '\0';
    memcpy(minor_str, dot_off_1 + 1, minor_len);
    minor_str[minor_len] = '\0';

    printf("%s | %s | %s\n", ver_str, major_str, minor_str);

    int parsed_major = atoi(major_str);
    int parsed_minor = atoi(minor_str);

    #= foreach api_versions =#
    AGLET_@{name} = (parsed_major > @{major} || (parsed_major == @{major} && parsed_minor >= @{minor})) ? 1 : 0;
    #= /foreach =#

    return 0;
}

static int _load_extensions(AgletLoadProc load_proc) {
    GLenum(*local_glGetError)() = (GLenum(*)()) load_proc("glGetError");
    if (local_glGetError == NULL) {
        return AGLET_ERROR_PROC_LOAD;
    }

    #ifdef GL_NUM_EXTENSIONS
    const GLubyte *(*local_glGetStringi)(GLenum name, GLuint index) = (const GLubyte*(*)(GLenum, GLuint)) load_proc("glGetStringi");
    void (*local_glGetIntegerv)(GLenum, GLint*) = (void(*)(GLenum, GLint*)) (void(*)(GLenum, GLint*)) load_proc("glGetIntegerv");
    if (local_glGetStringi != NULL && local_glGetIntegerv != NULL) {
        int num_exts = 0;
        local_glGetIntegerv(GL_NUM_EXTENSIONS, &num_exts);

        int gl_err = local_glGetError();
        if (gl_err == GL_NO_ERROR) {
        for (int i = 0; i < num_exts; i++) {
            const char *cur_ext = (const char *) local_glGetStringi(GL_EXTENSIONS, i);
            const size_t cur_len = strlen(cur_ext);

            #= foreach extensions =#
            if (strlen("@{name}") == cur_len && strncmp(cur_ext, "@{name}", cur_len) == 0) {
                AGLET_@{name} = 1;
                continue;
            }
            #= /foreach =#
        }

        return 0;
        } else if (gl_err != GL_INVALID_ENUM) {
            return AGLET_ERROR_GL_ERROR;
        }
    }
    #endif

    // fallback section

    const GLubyte *(*local_glGetString)(GLenum name) = (const GLubyte*(*)(GLenum)) load_proc("glGetString");

    if (local_glGetString == NULL) {
        return AGLET_ERROR_PROC_LOAD;
    }

    const char *exts_str = (const char *) local_glGetString(GL_EXTENSIONS);
    int glErr = local_glGetError();
    if (glErr != GL_NO_ERROR) {
        return glErr;
    }

    const char *cur_ext = NULL;
    const char *next_ext = exts_str;
    while (next_ext != NULL) {
        cur_ext = next_ext + 1;
        next_ext = strchr(cur_ext, ' ');

        size_t cur_len = next_ext != NULL ? (size_t) (next_ext - cur_ext) : strlen(cur_ext);

        if (cur_len == 0) {
            continue;
        }

        #= foreach extensions =#
        if (strlen("@{name}") == cur_len && strncmp(cur_ext, "@{name}", cur_len) == 0) {
            AGLET_@{name} = 1;
            continue;
        }
        #= /foreach =#
    }

    return 0;
}

static int _check_minimum_version() {
    if (!AGLET_@{min_api_version}) {
        fprintf(stderr, "[Aglet] Current environment does not support minimum @{api_name} version\n");
        return AGLET_ERROR_MINIMUM_VERSION;
    }

    return 0;
}

static int _check_required_extensions() {
    bool missing_ext = false;

    #= foreach extensions =#
    if (!AGLET_@{name}) {
        if (@{required}) {
            fprintf(stderr, "[Aglet] Required extension @{name} is not available\n");
            missing_ext = true;
        } else {
            fprintf(stderr, "[Aglet] Optional extension @{name} is not available\n");
        }
    }
    #= /foreach =#

    if (missing_ext) {
        return AGLET_ERROR_MISSING_EXTENSION;
    }

    return 0;
}

int agletLoadCapabilities(AgletLoadProc load_proc) {
    static bool _loaded_caps = false;

    if (_loaded_caps) {
        return 0;
    }

    int rc = 0;
    if ((rc = _load_versions(load_proc)) != 0) {
        fprintf(stderr, "[Aglet] Failed to query supported versions\\n");
        return rc;
    }

    if ((rc = _check_minimum_version()) != 0) {
        return rc;
    }

    if ((rc = _load_extensions(load_proc)) != 0) {
        fprintf(stderr, "[Aglet] Failed to query extensions (rc %d)\\n", rc);
        return rc;
    }

    if ((rc = _check_required_extensions()) != 0) {
        return rc;
    }

    _loaded_caps = true;

    return 0;
}

static int _load_procs(AgletLoadProc load_proc) {
    #= foreach procs =#
    aglet_@{name} = (PFN@{name_upper}PROC) load_proc("@{name}");
    #= /foreach =#

    return 0;
}

int agletLoad(AgletLoadProc load_proc) {
    int rc = 0;
    if ((rc = agletLoadCapabilities(load_proc)) != 0) {
        return rc;
    }

    if ((rc = _load_procs(load_proc)) != 0) {
        return rc;
    }

    return 0;
}

#ifdef __cplusplus
}
#endif
