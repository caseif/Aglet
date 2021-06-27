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
    "#{indent_space}#{str.gsub(/\n(.)/, "\n#{indent_space}\\1")}"
end

GL_REGISTRY_PATH = "#{__dir__}/specs/OpenGL-Registry/xml/gl.xml"

ADDR_ARR = 'opengl_proc_addrs'

ASM_COMMENT_PREFIX = '# '

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

static int _load_versions(AgletLoadProc load_proc) {
    //TODO
    return 0;
}

static int _load_extensions(AgletLoadProc load_proc) {
    const GLenum(*glGetError)() = load_proc(\"glGetError\");

    #ifdef GL_NUM_EXTENSIONS
    const GLubyte *(*glGetStringi)(GLenum name, GLuint index) = load_proc(\"glGetStringi\");
    void (*glGetIntegerv)(GLenum, GLint*) = load_proc(\"glGetIntegerv\");
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

    const GLubyte *(*glGetString)(GLenum name) = load_proc(\"glGetString\");

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

static int _load_procs(AgletLoadProc load_proc) {
%{proc_load_code}

    return 0;
}

int agletLoad(AgletLoadProc load_proc) {
    int rc = 0;
    if ((rc = _load_versions(load_proc)) != 0) {
        fprintf(stderr, \"[Aglet] Failed to query supported %{api} versions\\n\");
        return rc;
    }

    if ((rc = _load_extensions(load_proc)) != 0) {
        fprintf(stderr, \"[Aglet] Failed to query %{api} extensions (rc %%d)\\n\", rc);
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
"

EXTENSION_MATCH_TEMPLATE_C =
'if (strlen("%{name}") == cur_len && strncmp(cur_ext, "%{name}", cur_len) == 0) {
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

class ProcParam
    def initialize(name, type)
        @name = name
        @type = type
    end
    attr_reader :name
    attr_reader :type

    def gen_c()
        return "#{@type} #{@name}"
    end
end

class GLProc
    def initialize(name, ret_type, params)
        @name = name
        @ret_type = ret_type
        @params = params
    end
    attr_reader :name
    attr_reader :ret_type
    attr_reader :params
end

class GLType
    def initialize(name, typedef)
        @name = name
        @typedef = typedef
    end
    attr_reader :name
    attr_reader :typedef
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
end

class GLDefs
    def initialize(types, enums, procs)
        @types = types
        @enums = enums
        @procs = procs
    end
    attr_reader :types
    attr_reader :enums
    attr_reader :procs
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
    def initialize(api, base_api, version, extensions, type_names, enum_names, proc_names)
        @api = api
        @base_api = base_api
        @version = version
        @extensions = extensions
        @type_names = type_names
        @enum_names = enum_names
        @proc_names = proc_names
    end
    attr_reader :api
    attr_reader :base_api
    attr_reader :version
    attr_reader :extensions
    attr_reader :type_names
    attr_reader :enum_names
    attr_reader :proc_names
end

class TemplateSubs
    def initialize(name, subs)
        @name = name
        @subs = subs
    end
    attr_reader :name
    attr_reader :subs
end

def gen_from_template(template_path, subs_data)
    template_content = File.read template_path
    final_content = ''

    last_off = 0

    sec_templates = template_content.to_enum(:scan, /(?<start>%)\= foreach (?<name>.*?) \=%\n(?<content>.*?)\n%\= \/foreach \=%(?<end>\n)/m).map { Regexp.last_match }
    sec_templates.each do |s|
        sec_start = s.offset(:start)[0] - 1
        sec_end = s.offset(:end)[1]

        final_content << template_content[last_off..sec_start]
        last_off = sec_end

        sec_name = s.named_captures['name']
        sec_content = s.named_captures['content']
        sec_subs = subs_data[sec_name]
        next if not sec_subs

        sec_output = ''

        sec_subs.each do |sub_group|
            cur_content = sec_content.dup
            sub_group.each do |sub_item|
                cur_content.gsub! "@#{sub_item[0]}", sub_item[1]
            end

            sec_output << "#{cur_content}\n"
        end

        final_content << sec_output
    end

    final_content << template_content[last_off..]

    return final_content
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
    require_procs = []

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
        require_procs += require_secs.xpath('.//command/@name').map { |n| n.text }

        require_types -= remove_secs.xpath('.//type/@name').map { |n| n.text }
        require_enums -= remove_secs.xpath('.//enum/@name').map { |n| n.text }
        require_procs -= remove_secs.xpath('.//command/@name').map { |n| n.text }
    end

    profile_extensions = profile.xpath('//profile//extensions//extension')
        .map { |e| GLExtension.new(e.text, e.at_xpath('./@required').to_s.downcase == 'true') }

    ext_names = profile_extensions.map { |e| e.name }

    reg.xpath('//registry//extensions//extension').each do |ext|
        ext_name = ext.xpath('@name').text
        next unless ext_names.include? ext_name

        supported = ext.xpath('@supported').text
        if supported != nil and not supported.split('|').include? profile_api
            raise "Extension #{ext_name} is not supported by the selected API (#{profile_api})"
        end

        require_procs += ext.xpath('.//require//command/@name').map { |n| n.text }
        require_procs -= ext.xpath('.//remove//command/@name').map { |n| n.text }
    end

    print "Finished discovering members for profile \"#{profile_api} #{profile_version}\""
    print " (#{require_types.length} types, #{require_enums.length} enums, #{require_procs.length} functions)\n"

    return GLProfile.new(profile_api, profile_api_base, profile_version, profile_extensions, require_types.to_set, require_enums.to_set, require_procs.to_set)
end

def parse_param_type(raw)
    raw.gsub(/<name>.*<\/name>/, '').gsub(/<\/?ptype>/, '').gsub('* ', ' *')
end

def load_gl_members(reg, profile)
    types = []
    enums = []
    procs = []

    req_procs = profile.proc_names

    extra_types = Set[]

    # discover commands first because they can implicitly require extra types
    reg.xpath('//registry//commands//command').each do |cmd_root|
        cmd_name = cmd_root.xpath('.//proto//name')

        next unless req_procs.include? cmd_name.text

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
            params << ProcParam.new(param_name.strip, param_type)
        end

        procs << GLProc.new(name, ret, params)
    end

    req_types = profile.type_names + extra_types

    print "Discovered #{req_types.length - profile.type_names.length} additional types\n"

    more_types = Set[]

    reg.xpath('//registry//types/type').each do |type_root|
        next if name_attr = type_root.at_xpath('./@name') and
            (name_attr.text == 'khrplatform' or name_attr.text == 'GLhandleARB')

        type_name = type_root.xpath('.//name').text
        # bad idea to parse XML with regex, but this is extremely domain-specific
        type_typedef = type_root.to_s.gsub('<apientry/>', 'APIENTRY').gsub(/<.*?>/, '')

        types << GLType.new(type_name, type_typedef)
    end

    reg.xpath('//registry//enums/enum').each do |enum_root|
        enum_name = enum_root.xpath('./@name').text
        enum_group = enum_root.xpath('./@group').text
        enum_value = enum_root.xpath('./@value').text
        next if enum_api = enum_root.at_xpath('./@api') and enum_api != profile.base_api

        enums << GLEnum.new(enum_name, enum_group, enum_value)
    end

    GLDefs.new(types, enums, procs)
end

def generate_header(out_dir, profile, defs)
    out_file = File.open("#{out_dir}/aglet.h", 'w')

    subs_data = {}

    subs_data['type_defs'] = []
    defs.types.each do |t|
        subs_data['type_defs'] << {name: t.name, typedef: t.typedef}
    end

    subs_data['enum_defs'] = []
    defs.enums.group_by { |e| e.group }.each do |name, group|
        group.each do |e|
            subs_data['enum_defs'] << {name: e.name, value: e.value}
        end
    end
    
    subs_data['proc_defs'] = []
    defs.procs.each do |p|
        subs_data['proc_defs'] << {name: p.name, ret_type: p.ret_type, params: p.params.map { |p| p.gen_c }.join(', ')}
    end
    
    subs_data['ext_defs'] = []
    profile.extensions.each do |e|
        subs_data['ext_defs'] << {name: e.name}
    end
    
    out_file << gen_from_template("#{__dir__}/templates/c/aglet.h", subs_data)
    return
end

def generate_loader_source(out_dir, profile, defs)
    procs = defs.procs

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

    procs.each_with_index do |proc, i|
        proc_load_code << "    #{ADDR_ARR}[#{i}] = load_proc(\"#{proc.name}\");\n"
    end

    proc_load_code.delete_suffix! "\n"

    out_file << LOADER_TEMPLATE % [api: profile.api, num_procs: procs.size, proc_load_code: proc_load_code,
        ext_init_code: ext_init_code, ext_load_code: ext_load_code, ext_check_code: ext_check_code]
end

def generate_trampolines_amd64(out_dir, defs)
    procs = defs.procs

    out_file = File.open("#{out_dir}/aglet_trampolines.s", 'w')

    out_file << TRAMPOLINES_HEADER_AMD64

    procs.each_with_index do |proc, i|
        out_file << "\n"
        out_file << TRAMPOLINE_TEMPLATE_AMD64 % [name: proc.name, index: i]
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
