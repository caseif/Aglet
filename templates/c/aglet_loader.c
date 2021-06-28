/* Auto-generated file; do not modify! */

#include <aglet/aglet.h>

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

%= foreach procs =%
PFN@{name_upper}PROC aglet_@{name} = NULL;
%= /foreach =%

%= foreach extensions =%
int AGLET_@{name} = 0;
%= /foreach =%

static int _load_versions(AgletLoadProc load_proc) {
    //TODO
    return 0;
}

static int _load_extensions(AgletLoadProc load_proc) {
    const GLenum(*glGetError)() = load_proc("glGetError");

    #ifdef GL_NUM_EXTENSIONS
    const GLubyte *(*glGetStringi)(GLenum name, GLuint index) = load_proc("glGetStringi");
    void (*glGetIntegerv)(GLenum, GLint*) = load_proc("glGetIntegerv");
    if (glGetStringi != NULL && glGetIntegerv != NULL) {
        int num_exts = 0;
        glGetIntegerv(GL_NUM_EXTENSIONS, &num_exts);
        
        if (glGetError() != GL_NO_ERROR) {
            return AGLET_ERROR_GL_ERROR;
        }

        for (int i = 0; i < num_exts; i++) {
            const char *cur_ext = glGetStringi(GL_EXTENSIONS, i);
            const size_t cur_len = strlen(cur_ext);

            %= foreach extensions =%
            if (strlen("@{name}") == cur_len && strncmp(cur_ext, "@{name}", cur_len) == 0) {
                AGLET_@{name} = 1;
                continue;
            }
            %= /foreach =%
        }

        return 0;
    }
    #endif

    // fallback section

    const GLubyte *(*glGetString)(GLenum name) = load_proc("glGetString");

    if (glGetString == NULL) {
        return AGLET_ERROR_PROC_LOAD;
    }

    const char *exts_str = (const char *) glGetString(GL_EXTENSIONS);
    int glErr = glGetError();
    if (glErr != GL_NO_ERROR) {
        return glErr;
    }

    const char *cur_ext = exts_str;
    const char *next_ext = exts_str;
    while (next_ext != NULL) {
        cur_ext = next_ext + 1;
        next_ext = strchr(cur_ext, ' ');
        
        size_t cur_len = next_ext != NULL ? next_ext - cur_ext : strlen(cur_ext);

        if (cur_len == 0) {
            continue;
        }

        %= foreach extensions =%
        if (strlen("@{name}") == cur_len && strncmp(cur_ext, "@{name}", cur_len) == 0) {
            AGLET_@{name} = 1;
            continue;
        }
        %= /foreach =%
    }

    return 0;
}

static int _check_required_extensions() {
    bool missing_ext = false;

    %= foreach extensions =%
    if (!AGLET_@{name}) {
        fprintf(stderr, "[Aglet] Required extension @{name} is not available\n");
        missing_ext = true;
    }
    %= /foreach =%

    if (missing_ext) {
        return AGLET_ERROR_MISSING_EXTENSION;
    }

    return 0;
}

static int _load_procs(AgletLoadProc load_proc) {
    %= foreach procs =%
    aglet_@{name} = load_proc("@{name}");
    %= /foreach =%

    return 0;
}

int agletLoad(AgletLoadProc load_proc) {
    int rc = 0;
    if ((rc = _load_versions(load_proc)) != 0) {
        fprintf(stderr, "[Aglet] Failed to query supported %{api} versions\\n");
        return rc;
    }

    if ((rc = _load_extensions(load_proc)) != 0) {
        fprintf(stderr, "[Aglet] Failed to query %{api} extensions (rc %%d)\\n", rc);
        return rc;
    }

    if ((rc = _check_required_extensions(load_proc)) != 0) {
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
