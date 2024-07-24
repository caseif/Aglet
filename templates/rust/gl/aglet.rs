/* Auto-generated file; do not modify! */

#[allow(dead_code, non_camel_case_types)]
pub type GLbyte = i8;
#[allow(dead_code, non_camel_case_types)]
pub type GLubyte = u8;
#[allow(dead_code, non_camel_case_types)]
pub type GLshort = i16;
#[allow(dead_code, non_camel_case_types)]
pub type GLushort = u16;
#[allow(dead_code, non_camel_case_types)]
pub type GLint = i32;
#[allow(dead_code, non_camel_case_types)]
pub type GLuint = u32;
#[allow(dead_code, non_camel_case_types)]
pub type GLsizei = i32;
#[allow(dead_code, non_camel_case_types)]
pub type GLenum = u32;
#[allow(dead_code, non_camel_case_types)]
pub type GLboolean = u8;
#[allow(dead_code, non_camel_case_types)]
pub type GLbitfield = u32;
#[allow(dead_code, non_camel_case_types)]
pub type GLclampx = i32;
#[allow(dead_code, non_camel_case_types)]
pub type GLfloat = f32;
#[allow(dead_code, non_camel_case_types)]
pub type GLclampf = f32;
#[allow(dead_code, non_camel_case_types)]
pub type GLdouble = f64;
#[allow(dead_code, non_camel_case_types)]
pub type GLclampd = f64;
#[allow(dead_code, non_camel_case_types)]
pub type GLeglClientBufferEXT = *mut std::ffi::c_void;
#[allow(dead_code, non_camel_case_types)]
pub type GLeglImageOES = *mut std::ffi::c_void;
#[allow(dead_code, non_camel_case_types)]
pub type GLchar = i8;
#[allow(dead_code, non_camel_case_types)]
pub type GLcharARB = i8;
#[cfg(any(target_os = "macos", target_os = "ios"))]
#[allow(dead_code, non_camel_case_types)]
pub type GLhandleARB = *mut std::ffi::c_void;
#[cfg(not(any(target_os = "macos", target_os = "ios")))]
#[allow(dead_code, non_camel_case_types)]
pub type GLhandleARB = u32;
#[allow(dead_code, non_camel_case_types)]
pub type GLhalf = u16;
#[allow(dead_code, non_camel_case_types)]
pub type GLhalfARB = u16;
#[allow(dead_code, non_camel_case_types)]
pub type GLfixed = i32;
#[allow(dead_code, non_camel_case_types)]
pub type GLintptr = i64;
#[allow(dead_code, non_camel_case_types)]
pub type GLintptrARB = i64;
#[allow(dead_code, non_camel_case_types)]
pub type GLsizeiptr = isize;
#[allow(dead_code, non_camel_case_types)]
pub type GLsizeiptrARB = isize;
#[allow(dead_code, non_camel_case_types)]
pub type GLint64 = i64;
#[allow(dead_code, non_camel_case_types)]
pub type GLint64EXT = i64;
#[allow(dead_code, non_camel_case_types)]
pub type GLuint64 = u64;
#[allow(dead_code, non_camel_case_types)]
pub type GLuint64EXT = u64;
#[allow(dead_code, non_camel_case_types)]
pub type GLsync = *mut std::ffi::c_void;
#[allow(dead_code, non_camel_case_types)]
pub type GLDEBUGPROC = unsafe extern "C" fn(source: GLenum, ty: GLenum, id: GLuint, severity: GLenum, length: GLsizei, message: *const GLchar, userParam: *const std::ffi::c_void);
#[allow(dead_code, non_camel_case_types)]
pub type GLDEBUGPROCARB = GLDEBUGPROC;
#[allow(dead_code, non_camel_case_types)]
pub type GLDEBUGPROCKHR = GLDEBUGPROC;
#[allow(dead_code, non_camel_case_types)]
pub type GLDEBUGPROCAMD = unsafe extern "C" fn(id: GLuint, category: GLenum, severity: GLenum, length: GLsizei, message: *const GLchar, userParam: *mut std::ffi::c_void);
#[allow(dead_code, non_camel_case_types)]
pub type GLhalfNV = u16;
#[allow(dead_code, non_camel_case_types)]
pub type GLvdpauSurfaceNV = GLintptr;
#[allow(dead_code, non_camel_case_types)]
pub type GLVULKANPROCNV = unsafe extern "C" fn();

#[derive(std::fmt::Debug)]
pub enum AgletError {
    Unspecified = 1,
    ProcLoad = 2,
    GlError = 3,
    MinVersion = 4,
    MissingExtension = 5,
}

type AgletLoadProc = unsafe extern "C" fn(name: *const std::ffi::c_char) -> *mut std::ffi::c_void;

static mut DID_LOAD_CAPS: bool = false;

#= foreach api_versions =#
pub static mut AGLET_@{name}: bool = false;
#= /foreach =#

#= foreach extensions =#
#[allow(non_upper_case_globals, unused_variables)]
pub static mut AGLET_@{name}: bool = false;
#= /foreach =#

#= foreach enum_defs =#
#[allow(dead_code, non_upper_case_globals)]
pub const @{name}: u@{width} = @{value};
#= /foreach =#

#= foreach proc_defs =#
#[allow(non_camel_case_types)]
pub type PFN@{name_upper}PROC = unsafe extern "C" fn(@{params}) -> @{ret_type};
#= /foreach =#

#= foreach procs =#
#[allow(non_upper_case_globals)]
pub static mut aglet_@{name}: Option<PFN@{name_upper}PROC> = None;
#= /foreach =#

#= foreach proc_defs =#
#[allow(dead_code, non_snake_case)]
#[inline(always)]
pub unsafe extern "C" fn @{name}(@{params}) -> @{ret_type} { (aglet_@{name}.unwrap())(@{param_names}) }
#= /foreach =#

#[allow(dead_code, non_snake_case)]
unsafe fn load_versions(load_proc: AgletLoadProc) -> Result<(), AgletError> {
    let pn_glGetError = std::ffi::CString::new("glGetError").unwrap();
    let local_glGetError_ptr = load_proc(pn_glGetError.as_ptr());
    if local_glGetError_ptr.is_null() {
        return Err(AgletError::ProcLoad);
    }
    let local_glGetError: unsafe extern "C" fn() -> GLenum = std::mem::transmute(local_glGetError_ptr);

    #= if @{target_api_version_major} >= 3 =#
    let pn_glGetIntegerv = std::ffi::CString::new("glGetIntegerv").unwrap();
    let local_glGetIntegerv_ptr = load_proc(pn_glGetIntegerv.as_ptr());
    if local_glGetIntegerv_ptr.is_null() {
        return Err(AgletError::ProcLoad);
    }
    let local_glGetIntegerv: unsafe extern "C" fn(GLenum, *mut GLint) = std::mem::transmute(local_glGetIntegerv_ptr);

    let gl_err = local_glGetError();
    if gl_err == GL_NO_ERROR {
        let mut ver_major: i32 = 0;
        let mut ver_minor: i32 = 0;

        local_glGetIntegerv(GL_MAJOR_VERSION, &mut ver_major);
        if local_glGetError() != GL_NO_ERROR {
            return Err(AgletError::GlError);
        }

        local_glGetIntegerv(GL_MINOR_VERSION, &mut ver_minor);
        if local_glGetError() != GL_NO_ERROR {
            return Err(AgletError::GlError);
        }

        #= foreach api_versions =#
        AGLET_@{name} = ver_major > @{major} || (ver_major == @{major} && ver_minor >= @{minor});
        #= /foreach =#

        return Ok(());
    } else if gl_err != GL_INVALID_ENUM {
        return Err(AgletError::GlError);
    }
    #= /if =#

    // fallback section

    let pn_glGetString = std::ffi::CString::new("glGetString").unwrap();
    let local_glGetString_ptr = load_proc(pn_glGetString.as_ptr());
    if local_glGetString_ptr.is_null() {
        return Err(AgletError::ProcLoad);
    }
    let local_glGetString: unsafe extern "C" fn(GLenum) -> *const GLubyte = std::mem::transmute(local_glGetString_ptr);

    let ver_c_str: *const std::ffi::c_uchar = local_glGetString(GL_VERSION);
    if local_glGetError() != GL_NO_ERROR || ver_c_str.is_null() {
        return Err(AgletError::GlError);
    }

    let ver_str: std::string::String = std::ffi::CStr::from_ptr(ver_c_str.cast()).to_string_lossy().to_string();
    if !ver_str.as_str().contains(".") {
        eprintln!("[Aglet] GL returned nonsense version string {ver_str}");
        return Err(AgletError::Unspecified);
    }

    let (major_str, minor_str) = match ver_str.as_str().split_once(".") {
        Some(res) => res,
        None => {
            eprintln!("[Aglet] GL returned nonsense version string {ver_str}");
            return Err(AgletError::Unspecified);
        },
    };

    if major_str.is_empty() || minor_str.is_empty() {
        return Err(AgletError::Unspecified);
    }

    let parsed_major: i32 = match str::parse(major_str) {
        Ok(res) => res,
        Err(_) => return Err(AgletError::Unspecified),
    };
    let parsed_minor: i32 = match str::parse(minor_str) {
        Ok(res) => res,
        Err(_) => return Err(AgletError::Unspecified),
    };

    #= foreach api_versions =#
    if parsed_major > @{major} || (parsed_major == @{major} && parsed_minor >= @{minor}) {
        AGLET_@{name} = true;
    }
    #= /foreach =#

    return Ok(());
}

#[allow(dead_code, non_snake_case)]
unsafe fn load_extensions(load_proc: AgletLoadProc) -> Result<(), AgletError> {
    let pn_glGetError = std::ffi::CString::new("glGetError").unwrap();
    let local_glGetError_ptr = load_proc(pn_glGetError.as_ptr());
    if local_glGetError_ptr.is_null() {
        return Err(AgletError::ProcLoad);
    }
    let local_glGetError: unsafe extern "C" fn() -> GLenum = std::mem::transmute(local_glGetError_ptr);

    #= if @{target_api_version_major} >= 3 =#
    let pn_glGetStringi = std::ffi::CString::new("glGetStringi").unwrap();
    let pn_glGetIntegerv = std::ffi::CString::new("glGetIntegerv").unwrap();
    let local_glGetStringi_ptr = load_proc(pn_glGetStringi.as_ptr());
    let local_glGetIntegerv_ptr = load_proc(pn_glGetIntegerv.as_ptr());
    if !local_glGetStringi_ptr.is_null() && !local_glGetIntegerv_ptr.is_null() {
        let local_glGetStringi: unsafe extern "C" fn(GLenum, GLuint) -> *const GLubyte = std::mem::transmute(local_glGetStringi_ptr);
        let local_glGetIntegerv: unsafe extern "C" fn(GLenum, *mut GLint) = std::mem::transmute(local_glGetIntegerv_ptr);

        let mut num_exts: i32 = 0;
        local_glGetIntegerv(GL_NUM_EXTENSIONS, &mut num_exts);

        if num_exts < 0 {
            // this should never happen, something has gone catastrophically wrong
            return Err(AgletError::Unspecified);
        }

        let gl_err = local_glGetError();
        if gl_err == GL_NO_ERROR {
            for i in 0u32..(num_exts as u32) {
                let cur_ext: std::string::String = std::ffi::CStr::from_ptr(local_glGetStringi(GL_EXTENSIONS, i).cast()).to_string_lossy().to_string();

                #= foreach extensions =#
                if cur_ext == "@{name}" {
                    AGLET_@{name} = true;
                    continue;
                }
                #= /foreach =#
            }

            return Ok(());
        } else if gl_err != GL_INVALID_ENUM {
            return Err(AgletError::GlError);
        }
    }
    #= /if =#

    // fallback section

    let pn_glGetString = std::ffi::CString::new("glGetString").unwrap();
    let local_glGetString_ptr = load_proc(pn_glGetString.as_ptr());
    if local_glGetString_ptr.is_null() {
        return Err(AgletError::ProcLoad);
    }
    let local_glGetString: fn(GLenum) -> *const GLubyte = std::mem::transmute(local_glGetString_ptr);

    let exts_c_str: *const std::ffi::c_uchar = local_glGetString(GL_EXTENSIONS);
    let exts_str: std::string::String = std::ffi::CStr::from_ptr(exts_c_str.cast()).to_string_lossy().to_string();
    let gl_err = local_glGetError();
    if gl_err != GL_NO_ERROR {
        return Err(AgletError::GlError);
    }

    for ext in exts_str.as_str().split(",") {
        let ext_trimmed = ext.trim();
        if ext_trimmed.len() == 0 {
            continue;
        }

        #= foreach extensions =#
        if ext_trimmed == "@{name}" {
            AGLET_@{name} = true;
            continue;
        }
        #= /foreach =#
    }

    return Ok(());
}

#[allow(dead_code, non_snake_case)]
unsafe fn check_minimum_version() -> Result<(), AgletError> {
    if !AGLET_@{min_api_version} {
        eprintln!("[Aglet] Current environment does not support minimum @{api_name} version");
        return Err(AgletError::MinVersion);
    }

    return Ok(());
}

#[allow(dead_code, non_snake_case)]
unsafe fn check_required_extensions() -> Result<(), AgletError> {
    let mut missing_ext = false;

    #= foreach extensions =#
    if !AGLET_@{name} {
        if @{required} {
            eprintln!("[Aglet] Required extension @{name} is not available");
            missing_ext = true;
        } else {
            eprintln!("[Aglet] Optional extension @{name} is not available");
        }
    }
    #= /foreach =#

    if missing_ext {
        return Err(AgletError::MissingExtension);
    }

    return Ok(());
}

#[allow(dead_code, non_snake_case)]
unsafe fn load_procs(load_proc: AgletLoadProc) -> Result<(), AgletError> {
    #= foreach procs =#
    let pn_@{name} = std::ffi::CString::new("@{name}").unwrap();
    aglet_@{name} = Some(std::mem::transmute(load_proc(pn_@{name}.as_ptr())));
    #= /foreach =#

    return Ok(());
}

#[allow(dead_code, non_snake_case)]
pub(crate) fn agletLoadCapabilities(load_proc: AgletLoadProc) -> Result<(), AgletError> {
    unsafe {
        if DID_LOAD_CAPS {
            return Ok(());
        }

        if let Err(e) = load_versions(load_proc) {
            eprintln!("[Aglet] Failed to query supported versions");
            return Err(e);
        }

        if let Err(e) = check_minimum_version() {
            return Err(e);
        }

        if let Err(e) = load_extensions(load_proc) {
            eprintln!("[Aglet] Failed to query extensions (error type: {:?})", e);
            return Err(e);
        }

        if let Err(e) = check_required_extensions() {
            return Err(e);
        }

        DID_LOAD_CAPS = true;

        return Ok(());
    }
}

#[allow(dead_code, non_snake_case)]
pub(crate) fn agletLoad(load_proc: AgletLoadProc) -> Result<(), AgletError> {
    unsafe {
        if let Err(e) = agletLoadCapabilities(load_proc) {
            return Err(e);
        }

        if let Err(e) = load_procs(load_proc) {
            return Err(e);
        }

        return Ok(());
    }
}
