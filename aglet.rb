#!/usr/bin/env ruby

require 'nokogiri'
require 'optparse'

GL_REGISTRY_PATH = "#{__dir__}/specs/OpenGL-Registry/xml/gl.xml"

GL_PROC_TYPE = "GLFWglproc"
GL_LOOKUP_FN = "glfwGetProcAddress"
ADDR_ARR = 'opengl_fn_addrs'

ASM_COMMENT_PREFIX = '# '

C_HEADER =
'/* Auto-generated file; do not modify! */

#define GL_GLEXT_PROTOTYPES

#include "GLFW/glfw3.h"
'

ASM_HEADER =
ASM_COMMENT_PREFIX + 'Auto-generated file; do not modify!

.intel_syntax noprefix

.extern ' + ADDR_ARR + '
.text
'

ASM_FN_TEMPLATE_X64 =
'.global %{name}
%{name}:
    movq r11, [' + ADDR_ARR + '@GOTPCREL[rip]]
    jmp [r11]+%{index}*8
'

INIT_CODE_GLOBAL =
"#{GL_PROC_TYPE} #{ADDR_ARR}[%d];

void agletLoad() {
%s
}
"

class FnParam
    def initialize(name, type)
        @name = name
        @type = type
    end
    attr_reader :name
    attr_reader :type

    def to_s()
        return "#{@type} #{@name}"
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

    def to_s()
        fn_def = "#{@ret_type} #{@name}(#{params.join ', '})"
        return fn_def
    end
end

def params_to_str(params)
    params.join(', ')
end

def parse_args()
    options = {}
    OptionParser.new do |opts|
        opts.banner = "Usage: aglet.rb -p <profile> -o <output dir>"

        opts.on('-p PROFILE', '--profile=PROFILE', 'Path to profile file') do |p|
            options[:profile] = p
        end
        opts.on('-o OUTPUT', '--output=OUTPUT', 'Path to output directory') do |o|
            options[:output] = o
        end
    end.parse!

    raise "Profile path is required" unless options[:profile]
    raise "Output path is required" unless options[:output]

    options
end

def get_requested_fn_names(reg, profile_path)
    require_fns = []
    remove_fns = []

    profile = File.open(profile_path) { |f| Nokogiri::XML(f) }
    profile_api = profile.xpath('//profile/api/text()').text
    profile_core = profile.xpath('//profile/core/text()').text
    profile_version = profile.xpath('//profile//apiVersion/text()').text

    req_major, req_minor = profile_version.split('.')

    gl_feature_spec = reg.xpath('//registry//feature[@api="%s"]' % profile_api)
    gl_feature_spec.each do |ver|
        feature_number = ver.xpath('@number').text
        feature_major, feature_minor = feature_number.split('.')
        next if feature_major > req_major or (feature_major == req_major and feature_minor > req_minor)

        require_fns.concat ver.xpath('.//require//command/@name').map { |c| c.text }
        remove_fns.concat ver.xpath('.//remove[@profile="core"]//command/@name').map { |c| c.text } if profile_core
    end

    profile_extensions = profile.xpath('//profile//extensions//extension/text()').map { |e| e.text }

    support_api = profile_api.dup
    support_api.concat 'core' if support_api == 'gl' and profile_core

    reg.xpath('//registry//extensions//extension').each do |ext|
        supported = ext.xpath('@supported').text
        next unless supported == nil or supported.split('|').include? profile_api

        ext_name = ext.xpath('@name').text
        next unless profile_extensions.include? ext_name

        require_fns.concat ext.xpath('.//require//command/@name').map { |n| n.text }
        remove_fns.concat ext.xpath('.//remove//command/@name').map { |n| n.text }
    end

    final_fns = require_fns - remove_fns

    fmt_version = profile_version + (profile_core ? ' (core)' : '')
    print "Found #{final_fns.length} functions for profile \"#{profile_api} #{fmt_version}\"\n"

    return final_fns
end

def parse_param_type(raw)
    raw.gsub(/<name>.*<\/name>/, '').gsub(/<\/?ptype>/, '')
end

def load_fn_defs(reg, req_fns)
    fns = []

    reg.xpath("//registry//commands//command").each do |cmd_root|
        cmd_name = cmd_root.xpath('.//proto//name')

        next unless req_fns.include? cmd_name.text

        name = cmd_name.text.strip

        ret = parse_param_type cmd_root.xpath('.//proto').inner_html
        ret.strip!

        params = []

        cmd_root.xpath('.//param').each do |cmd_param|
            param_name = cmd_param.xpath('.//name').text
            param_type = parse_param_type cmd_param.inner_html
            params << FnParam.new(param_name.strip, param_type.strip)
        end

        fns << GLFunction.new(name, ret, params)
    end

    fns
end

def write_src_file(out_cpp, out_s, fns, per_context)
    out_cpp << CPP_HEADER
    out_cpp << "\n"

    out_s << ASM_HEADER

    init_code = ''
    decl_code = ''

    fns.each_with_index do |fn, i|
        init_code << "        #{ADDR_ARR}[#{i}] = #{GL_LOOKUP_FN}(\"#{fn.name}\");\n"

        typed_params = fn.params.join ', '
        untyped_params = fn.params.map { |p| p.name }.join ', '

        decl_code << "\n"
        decl_code << ASM_FN_TEMPLATE_X64 % [name: fn.name, index: i]
    end

    init_code.delete_suffix! "\n"

    out_cpp << INIT_CODE_GLOBAL % [fns.size, init_code]

    out_s << decl_code
end

args = parse_args

reg = File.open(GL_REGISTRY_PATH) { |f| Nokogiri::XML(f) }

req_fns = get_requested_fn_names(reg, args[:profile])
fn_defs = load_fn_defs(reg, req_fns)

out_dir_path = args[:output]
out_cpp = File.open(out_dir_path + "/aglet.c", 'w')
out_s = File.open(out_dir_path + "/aglet.s", 'w')

write_src_file(out_cpp, out_s, fn_defs, false)
