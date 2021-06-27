#!/usr/bin/env ruby

require 'fileutils'
require 'nokogiri'
require 'optparse'
require 'set'

def indent(str, cols)
    indent_space = ''
    for i in 1..cols
        indent_space << ' '
    end
    "#{indent_space}#{str.gsub(/\n/, "\n#{indent_space}")}"
end

GL_REGISTRY_PATH = "#{__dir__}/specs/OpenGL-Registry/xml/gl.xml"

ADDR_ARR = 'opengl_fn_addrs'

ASM_COMMENT_PREFIX = '# '

H_HEADER =
'/* Auto-generated file; do not modify! */

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

#define AGLET_ERROR_PROC_LOAD 1
#define AGLET_ERROR_GL_ERROR 2
#define AGLET_ERROR_MINIMUM_VERSION 3
#define AGLET_ERROR_MISSING_EXTENSION 4

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

typedef void *(*AgletLoadProc)(const char *name);
'

H_FOOTER =
'int agletLoad(AgletLoadProc load_proc_fn);

#ifdef __cplusplus
}
#endif
'

TRAMPOLINES_HEADER_AMD64 =
ASM_COMMENT_PREFIX + 'Auto-generated file; do not modify!

.intel_syntax noprefix

.extern ' + ADDR_ARR + '
.text
'

TRAMPOLINE_TEMPLATE_AMD64 =
'.global %{name}
%{name}:
    movq r11, [' + ADDR_ARR + '@GOTPCREL[rip]]
    jmp [r11]+%{index}*8
'

LOADER_TEMPLATE =
"/* Auto-generated file; do not modify! */

#include <aglet/aglet.h>

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#ifdef __cplusplus
extern \"C\" {
#endif

void *#{ADDR_ARR}[%{num_procs}];

%{ext_init_code}

static int _load_versions(AgletLoadProc load_proc_fn) {
    //TODO
    return 0;
}

static int _load_extensions(AgletLoadProc load_proc_fn) {
    const GLenum(*glGetError)() = load_proc_fn(\"glGetError\");

    #ifdef GL_NUM_EXTENSIONS2
    const GLubyte *(*glGetStringi)(GLenum name, GLuint index) = load_proc_fn(\"glGetStringi\");
    void (*glGetIntegerv)(GLenum, GLint*) = load_proc_fn(\"glGetIntegerv\");
    if (glGetStringi != NULL && glGetIntegerv != NULL) {
        int num_exts = 0;
        glGetIntegerv(GL_NUM_EXTENSIONS, &num_exts);
        
        if (glGetError() != GL_NO_ERROR) {
            return AGLET_ERROR_GL_ERROR;
        }

        for (int i = 0; i < num_exts; i++) {
            const char *cur_ext = glGetStringi(GL_EXTENSIONS, i);
            const size_t cur_len = strlen(cur_ext);

%{ext_load_code}
        }

        return 0;
    }
    #endif

    // fallback section

    const GLubyte *(*glGetString)(GLenum name) = load_proc_fn(\"glGetString\");

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

%{ext_load_code}
    }

    return 0;
}

static int _check_required_extensions() {
    bool missing_ext = false;
%{ext_check_code}

    if (missing_ext) {
        return AGLET_ERROR_MISSING_EXTENSION;
    }

    return 0;
}

static int _load_procs(AgletLoadProc load_proc_fn) {
%{proc_load_code}

    return 0;
}

int agletLoad(AgletLoadProc load_proc_fn) {
    int rc = 0;
    if ((rc = _load_versions(load_proc_fn)) != 0) {
        fprintf(stderr, \"[Aglet] Failed to query supported %{api} versions\\n\");
        return rc;
    }

    if ((rc = _load_extensions(load_proc_fn)) != 0) {
        fprintf(stderr, \"[Aglet] Failed to query %{api} extensions (rc %%d)\\n\", rc);
        return rc;
    }

    if ((rc = _check_required_extensions(load_proc_fn)) != 0) {
        return rc;
    }

    if ((rc = _load_procs(load_proc_fn)) != 0) {
        return rc;
    }

    return 0;
}

#ifdef __cplusplus
}
#endif
"

EXTENSION_MATCH_TEMPLATE_C =
'if (strncmp(cur_ext, "%{name}", cur_len) == 0) {
    AGLET_%{name} = 1;
    continue;
}
'

EXTENSION_REQUIRED_TEMPLATE_C =
'if (!AGLET_%{name}) {
    fprintf(stderr, "[Aglet] Required extension %{name} is not available\n");
    missing_ext = true;
}
'

class FnParam
    def initialize(name, type)
        @name = name
        @type = type
    end
    attr_reader :name
    attr_reader :type

    def gen_c()
        return "#{@type} #{@name}".gsub('* ', ' *')
    end
end

class GLFunction
    def initialize(name, ret_type, params)
        @name = name
        @ret_type = ret_type
        @params = params
    end
    attr_reader :name
    attr_reader :ret_type
    attr_reader :params

    def gen_c()
        fn_name_and_ret = "#{@ret_type} #{@name}".gsub('* ', ' *')
        fn_def = "APIENTRY #{fn_name_and_ret}(#{params.map { |p| p.gen_c }.join(', ')})"
        return fn_def
    end
end

class GLType
    def initialize(name, typedef)
        @name = name
        @typedef = typedef
    end
    attr_reader :name
    attr_reader :typedef

    def gen_c()
        return "#{typedef}"
    end
end

class GLEnum
    def initialize(name, group, value)
        @name = name
        @group = group
        @value = value
    end
    attr_reader :name
    attr_reader :group
    attr_reader :value

    def gen_c()
        return "#define #{name} #{value}"
    end
end

class GLDefs
    def initialize(types, enums, fns)
        @types = types
        @enums = enums
        @fns = fns
    end
    attr_reader :types
    attr_reader :enums
    attr_reader :fns
end

class GLExtension
    def initialize(name, required)
        @name = name
        @required = required
    end
    attr_reader :name
    attr_reader :required
end

class GLProfile
    def initialize(api, base_api, version, extensions, type_names, enum_names, fn_names)
        @api = api
        @base_api = base_api
        @version = version
        @extensions = extensions
        @type_names = type_names
        @enum_names = enum_names
        @fn_names = fn_names
    end
    attr_reader :api
    attr_reader :base_api
    attr_reader :version
    attr_reader :extensions
    attr_reader :type_names
    attr_reader :enum_names
    attr_reader :fn_names
end

def params_to_str(params)
    params.join(', ')
end

def parse_args()
    options = {}
    OptionParser.new do |opts|
        opts.banner = "Usage: aglet.rb -p <profile> -h <output dir>"

        opts.on('-p PROFILE', '--profile=PROFILE', 'Path to profile file') do |p|
            options[:profile] = p
        end
        opts.on('-o OUTPUT', '--output=OUTPUT', 'Path to output directory') do |h|
            options[:output] = h
        end
    end.parse!

    raise "Profile path is required" unless options[:profile]
    raise "Output path is required" unless options[:output]

    options
end

def load_profile(reg, profile_path)
    require_types = []
    require_enums = []
    require_fns = []

    profile = File.open(profile_path) { |f| Nokogiri::XML(f) }
    profile_api = profile.xpath('//profile/api/text()').text
    profile_api_base = profile_api == 'glcore' ? 'gl' : profile_api
    profile_version = profile.xpath('//profile//apiVersion/text()').text

    req_major, req_minor = profile_version.split('.')

    gl_feature_spec = reg.xpath('//registry//feature[@api="%s"]' % profile_api_base)
    gl_feature_spec.each do |ver|
        feature_number = ver.xpath('@number').text
        feature_major, feature_minor = feature_number.split('.')
        next if feature_major > req_major or (feature_major == req_major and feature_minor > req_minor)

        if profile_api == 'glcore'
            require_secs = ver.css("require:not([profile]), require[profile='core']")
            remove_secs = ver.css("remove:not([profile]), remove[profile='core']")
        elsif profile_api == 'gl'
            require_secs = ver.css("require:not([profile]), require[profile='compatibility']")
            remove_secs = ver.css("remove:not([profile]), remove[profile='compatibility']")
        end

        require_types += require_secs.xpath('.//type/@name').map { |n| n.text }
        require_enums += require_secs.xpath('.//enum/@name').map { |n| n.text }
        require_fns += require_secs.xpath('.//command/@name').map { |n| n.text }

        require_types -= remove_secs.xpath('.//type/@name').map { |n| n.text }
        require_enums -= remove_secs.xpath('.//enum/@name').map { |n| n.text }
        require_fns -= remove_secs.xpath('.//command/@name').map { |n| n.text }
    end

    profile_extensions = profile.xpath('//profile//extensions//extension')
        .map { |e| GLExtension.new(e.text, e.xpath('./@required')) }

    ext_names = profile_extensions.map { |e| e.name }

    reg.xpath('//registry//extensions//extension').each do |ext|
        ext_name = ext.xpath('@name').text
        next unless ext_names.include? ext_name

        supported = ext.xpath('@supported').text
        if supported != nil and not supported.split('|').include? profile_api
            raise "Extension #{ext_name} is not supported by the selected API (#{profile_api})"
        end

        require_fns += ext.xpath('.//require//command/@name').map { |n| n.text }
        require_fns -= ext.xpath('.//remove//command/@name').map { |n| n.text }
    end

    print "Finished discovering members for profile \"#{profile_api} #{profile_version}\""
    print " (#{require_types.length} types, #{require_enums.length} enums, #{require_fns.length} functions)\n"

    return GLProfile.new(profile_api, profile_api_base, profile_version, profile_extensions, require_types.to_set, require_enums.to_set, require_fns.to_set)
end

def parse_param_type(raw)
    raw.gsub(/<name>.*<\/name>/, '').gsub(/<\/?ptype>/, '').gsub('* ', ' *')
end

def load_gl_members(reg, profile)
    types = []
    enums = []
    fns = []

    req_fns = profile.fn_names

    extra_types = Set[]

    # discover commands first because they can implicitly require extra types
    reg.xpath('//registry//commands//command').each do |cmd_root|
        cmd_name = cmd_root.xpath('.//proto//name')

        next unless req_fns.include? cmd_name.text

        name = cmd_name.text.strip

        proto = cmd_root.xpath('.//proto')
        ret = parse_param_type proto.inner_html
        ret.gsub!(' *', '* ')
        ret.strip!

        if ptype = proto.at_xpath('.//ptype')
            extra_types << ptype.text
        end

        params = []

        cmd_root.xpath('.//param').each do |cmd_param|
            if ptype = cmd_param.at_xpath('.//ptype')
                extra_types << ptype.text
            end

            param_name = cmd_param.xpath('.//name').text
            param_type = parse_param_type cmd_param.inner_html
            param_type.gsub!(' *', '* ')
            param_type.strip!
            params << FnParam.new(param_name.strip, param_type)
        end

        fns << GLFunction.new(name, ret, params)
    end

    req_types = profile.type_names + extra_types

    print "Discovered #{req_types.length - profile.type_names.length} additional types\n"

    more_types = Set[]

    reg.xpath('//registry//types/type').each do |type_root|
        type_name = type_root.xpath('.//name').text
        type_typedef = type_root.text

        types << GLType.new(type_name, type_typedef)
    end

    reg.xpath('//registry//enums/enum').each do |enum_root|
        enum_name = enum_root.xpath('./@name').text
        enum_group = enum_root.xpath('./@group').text
        enum_value = enum_root.xpath('./@value').text
        next if enum_api = enum_root.at_xpath('./@api') and enum_api != profile.base_api

        enums << GLEnum.new(enum_name, enum_group, enum_value)
    end

    GLDefs.new(types, enums, fns)
end

def generate_header(out_dir, profile, defs)
    out_file = File.open("#{out_dir}/aglet.h", 'w')

    out_file << H_HEADER

    out_file << "\n"

    defs.types.each do |t|
        out_file << "#{t.gen_c}\n"
        if t.typedef =~ /^#include/
            out_file << "\n"
        end
    end

    out_file << "\n"

    defs.enums.group_by { |e| e.group }.each do |name, group|
        if group != ''
            out_file << "// enum group #{name}\n"
        else
            out_file << "// ungrouped\n"
        end
        group.each do |e|
            out_file << "#{e.gen_c}\n"
        end
        out_file << "\n"
    end

    out_file << "\n"

    defs.fns.each do |fn|
        out_file << "#{fn.gen_c};\n"
    end

    out_file << "\n"

    profile.extensions.each do |e|
        out_file << "GLAPI int AGLET_#{e.name};\n"
    end

    out_file << "\n"

    out_file << H_FOOTER
end

def generate_loader_source(out_dir, profile, defs)
    fns = defs.fns

    out_file = File.open("#{out_dir}/aglet_loader.c", 'w')

    ext_init_code = ''
    ext_load_code = ''
    ext_check_code = ''
    proc_load_code = ''

    profile.extensions.each do |e|
        ext_init_code << "int AGLET_#{e.name} = 0;"

        #TODO: the substitution happens twice and the indent is wrong for one of them
        ext_load_code << indent(EXTENSION_MATCH_TEMPLATE_C % [name: e.name], 12)

        ext_check_code << indent(EXTENSION_REQUIRED_TEMPLATE_C % [name: e.name], 4) if e.required
    end

    fns.each_with_index do |fn, i|
        proc_load_code << "    #{ADDR_ARR}[#{i}] = load_proc_fn(\"#{fn.name}\");\n"
    end

    proc_load_code.delete_suffix! "\n"

    out_file << LOADER_TEMPLATE % [api: profile.api, num_procs: fns.size, proc_load_code: proc_load_code,
        ext_init_code: ext_init_code, ext_load_code: ext_load_code, ext_check_code: ext_check_code]
end

def generate_trampolines_amd64(out_dir, defs)
    fns = defs.fns

    out_file = File.open("#{out_dir}/aglet_trampolines.s", 'w')

    out_file << TRAMPOLINES_HEADER_AMD64

    fns.each_with_index do |fn, i|
        out_file << "\n"
        out_file << TRAMPOLINE_TEMPLATE_AMD64 % [name: fn.name, index: i]
    end
end

args = parse_args

reg = File.open(GL_REGISTRY_PATH) { |f| Nokogiri::XML(f) }

profile = load_profile(reg, args[:profile])
defs = load_gl_members(reg, profile)

out_path = args[:output]
base_header_out_path = "#{out_path}/include"
aglet_header_out_path = "#{base_header_out_path}/aglet"
source_out_path = "#{out_path}/src"

FileUtils.mkdir_p aglet_header_out_path
FileUtils.mkdir_p source_out_path

generate_header(aglet_header_out_path, profile, defs)
generate_loader_source(source_out_path, profile, defs)
generate_trampolines_amd64(source_out_path, defs)

khr_header_out_path = "#{aglet_header_out_path}/KHR"
FileUtils.mkdir_p khr_header_out_path
FileUtils.cp("#{__dir__}/specs/EGL-Registry/api/KHR/khrplatform.h", "#{khr_header_out_path}/khrplatform.h")
