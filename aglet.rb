#!/usr/bin/env ruby

require 'bundler/setup'
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

API_GL = 'gl'
API_GL_CORE = 'glcore'
API_GLES = 'gles'
API_GLSC = 'glsc'

FEATURE_API_GL = 'gl'
FEATURE_API_GLES_1 = 'gles1'
FEATURE_API_GLES_2 = 'gles2'
FEATURE_API_GLSC_2 = 'glsc2'

API_FAMILY_GL = 'gl'

TEMPLATE_PLACE_VERSIONS = 'api_versions'
TEMPLATE_PLACE_TYPE_DEFS = 'type_defs'
TEMPLATE_PLACE_ENUM_DEFS = 'enum_defs'
TEMPLATE_PLACE_PROC_DEFS = 'proc_defs'
TEMPLATE_PLACE_PROCS = 'procs'
TEMPLATE_PLACE_EXTENSION_DEFS = 'ext_defs'
TEMPLATE_PLACE_EXTENSIONS = 'extensions'

GL_REGISTRY_PATH = "#{__dir__}/specs/OpenGL-Registry/xml/gl.xml"
VK_REGISTRY_PATH = "#{__dir__}/specs/OpenGL-Registry/xml/gl.xml"

KHR_HEADER_PATH = "#{__dir__}/specs/EGL-Registry/api/KHR/khrplatform.h"

C_TEMPLATES_PATH = "#{__dir__}/templates/c"
C_GL_TEMPLATES_PATH = "#{C_TEMPLATES_PATH}/gl"
C_GL_HEADER_TEMPLATE_PATH = "#{C_GL_TEMPLATES_PATH}/aglet.h"
C_GL_LOADER_TEMPLATE_PATH = "#{C_GL_TEMPLATES_PATH}/aglet_loader.c"

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

class ApiVersion
    def initialize(api, name, major, minor)
        @api = api
        @name = name
        @major = major
        @minor = minor
    end
    attr_reader :api
    attr_reader :name
    attr_reader :major
    attr_reader :minor
end

class ApiProc
    def initialize(name, ret_type, params)
        @name = name
        @ret_type = ret_type
        @params = params
    end
    attr_reader :name
    attr_reader :ret_type
    attr_reader :params
end

class ApiType
    def initialize(name, typedef)
        @name = name
        @typedef = typedef
    end
    attr_reader :name
    attr_reader :typedef
end

class ApiEnum
    def initialize(name, group, value)
        @name = name
        @group = group
        @value = value
    end
    attr_reader :name
    attr_reader :group
    attr_reader :value
end

class ApiDefs
    def initialize(versions, types, enums, procs)
        @versions = versions
        @types = types
        @enums = enums
        @procs = procs
    end
    attr_reader :versions
    attr_reader :types
    attr_reader :enums
    attr_reader :procs
end

class ApiExtension
    def initialize(name, required)
        @name = name
        @required = required
    end
    attr_reader :name
    attr_reader :required
end

class ApiProfile
    def initialize(api, feature_api, api_family, version, extensions)
        @api = api
        @feature_api = feature_api
        @api_family = api_family
        @version = version
        @extensions = extensions
    end
    attr_reader :api
    attr_reader :feature_api
    attr_reader :api_family
    attr_reader :version
    attr_reader :extensions
end

class ApiMembers
    def initialize(type_names, enum_names, proc_names)
        @type_names = type_names
        @enum_names = enum_names
        @proc_names = proc_names
    end
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

    sec_templates = template_content.to_enum(:scan, /(?<start>[ \t]*#)\= foreach (?<name>.*?) \=#\n(?<content>.*?)\n[ \t]*#\= \/foreach \=#(?<end>\n)/m).map { Regexp.last_match }
    sec_templates.each do |s|
        sec_start = s.offset(:start)[0] - 1
        sec_end = s.end(:end)

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
                cur_content.gsub! "@{#{sub_item[0]}}", sub_item[1]
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

def load_profile(profile_path)
    profile = File.open(profile_path) { |f| Nokogiri::XML(f) }
    api = profile.xpath('//profile/api//name/text()').text
    version = profile.xpath('//profile//api//version/text()').text

    feature_api = ''
    api_family = ''
    if api == API_GL_CORE or api == API_GL
        feature_api = FEATURE_API_GL
        api_family = API_FAMILY_GL
    elsif api == API_GLES
        if version.start_with? '1.'
            feature_api = FEATURE_API_GLES_1
        else
            feature_api = FEATURE_API_GLES_2
        end
        api_family = API_FAMILY_GL
    elsif api == API_GLSC
        feature_api = FEATURE_API_GLSC_2
        api_family = API_FAMILY_GL
    else
        print "Unrecognized API '#{api}'\n"
        return nil
    end

    extensions = profile.xpath('//profile//extensions//extension')
        .map { |e| ApiExtension.new(e.text, e.at_xpath('./@required').to_s.downcase == 'true') }

    return ApiProfile.new(api, feature_api, api_family, version, extensions)
end

def load_profile_members(reg, profile)
    require_types = []
    require_enums = []
    require_procs = []

    req_major, req_minor = profile.version.split('.')

    seen_vers = 0
    gl_feature_spec = reg.xpath('//registry//feature[@api="%s"]' % profile.feature_api)
    gl_feature_spec.each do |ver|
        feature_number = ver.xpath('@number').text
        feature_major, feature_minor = feature_number.split('.')
        next if feature_major > req_major or (feature_major == req_major and feature_minor > req_minor)

        seen_vers += 1

        if profile.feature_api == FEATURE_API_GL
            if profile.api == API_GL_CORE
                require_secs = ver.css("require:not([profile]), require[profile='core']")
                remove_secs = ver.css("remove:not([profile]), remove[profile='core']")
            else profile.api == API_GL
                require_secs = ver.css("require:not([profile]), require[profile='compatibility']")
                remove_secs = ver.css("remove:not([profile]), remove[profile='compatibility']")
            end
        else
            require_secs = ver.xpath('./require')
            remove_secs = ver.xpath('./remove')
        end

        require_types += require_secs.xpath('.//type/@name').map { |n| n.text }.flatten
        require_enums += require_secs.xpath('.//enum/@name').map { |n| n.text }.flatten
        require_procs += require_secs.xpath('.//command/@name').map { |n| n.text }.flatten

        require_types -= remove_secs.xpath('.//type/@name').map { |n| n.text }.flatten
        require_enums -= remove_secs.xpath('.//enum/@name').map { |n| n.text }.flatten
        require_procs -= remove_secs.xpath('.//command/@name').map { |n| n.text }.flatten
    end

    if seen_vers == 0
        print "Requested profile does not seem to include any defined versions\n"
        return nil
    end

    ext_names = profile.extensions.map { |e| e.name }

    reg.xpath('//registry//extensions//extension').each do |ext|
        ext_name = ext.xpath('@name').text
        next unless ext_names.include? ext_name

        supported = ext.xpath('@supported').text
        if supported != nil and not supported.split('|').include? profile.api
            raise "Extension #{ext_name} is not supported by the selected API (#{profile.api})"
        end

        require_types += ext.xpath('.//require/type/@name').map { |n| n.text }.flatten
        require_enums += ext.xpath('.//require/enum/@name').map { |n| n.text }.flatten
        require_procs += ext.xpath('.//require//command/@name').map { |n| n.text }.flatten
        require_types -= ext.xpath('.//remove//type/@name').map { |n| n.text }.flatten
        require_enums -= ext.xpath('.//remove//enum/@name').map { |n| n.text }.flatten
        require_procs -= ext.xpath('.//remove//command/@name').map { |n| n.text }.flatten
    end

    print "Finished discovering members for profile \"#{profile.api} #{profile.version}\""
    print " (#{require_types.length} types, #{require_enums.length} enums, #{require_procs.length} functions)\n"

    return ApiMembers.new(require_types.to_set, require_enums.to_set, require_procs.to_set)
end

def parse_param_type(raw)
    raw.gsub(/<name>.*<\/name>/, '').gsub(/<\/?ptype>/, '').gsub('* ', ' *')
end

def load_gl_defs(reg, profile, members)
    versions = []
    types = []
    enums = []
    procs = []

    gl_feature_spec = reg.xpath('//registry//feature[@api="%s"]' % profile.feature_api)
    gl_feature_spec.each do |ver|
        feature_number = ver.xpath('@number').text
        feature_name = ver.xpath('@name').text
        feature_major, feature_minor = feature_number.split('.')
        versions << ApiVersion.new(profile.feature_api, feature_name, feature_major, feature_minor)
    end

    req_procs = members.proc_names

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

        procs << ApiProc.new(name, ret, params)
    end

    req_types = members.type_names + extra_types

    print "Discovered #{req_types.length - members.type_names.length} additional types\n"

    more_types = Set[]

    reg.xpath('//registry//types/type').each do |type_root|
        next if name_attr = type_root.at_xpath('./@name') and
            (name_attr.text == 'khrplatform' or
                (profile.api_family == API_FAMILY_GL and name_attr.text == 'GLhandleARB'))

        type_name = type_root.xpath('.//name').text
        next unless req_types.include? type_name
        # bad idea to parse XML with regex, but this is extremely domain-specific
        type_typedef = type_root.to_s.gsub('<apientry/>', 'APIENTRY').gsub(/<.*?>/, '')

        types << ApiType.new(type_name, type_typedef)
    end

    reg.xpath('//registry//enums/enum').each do |enum_root|
        enum_name = enum_root.xpath('./@name').text
        enum_group = enum_root.xpath('./@group').text
        enum_value = enum_root.xpath('./@value').text
        next if enum_api = enum_root.at_xpath('./@api') and enum_api != profile.feature_api
        next unless members.enum_names.include? enum_name

        enums << ApiEnum.new(enum_name, enum_group, enum_value)
    end

    ApiDefs.new(versions, types, enums, procs)
end

def generate_header(out_dir, profile, defs)
    out_file = File.open("#{out_dir}/aglet.h", 'w')

    subs_data = {}

    subs_data[TEMPLATE_PLACE_VERSIONS] = []
    defs.versions.each do |v|
        subs_data[TEMPLATE_PLACE_VERSIONS] << {name: v.name.upcase, major: v.major, minor: v.minor}
    end

    subs_data[TEMPLATE_PLACE_TYPE_DEFS] = []
    defs.types.each do |t|
        subs_data[TEMPLATE_PLACE_TYPE_DEFS] << {name: t.name, typedef: t.typedef}
    end

    subs_data[TEMPLATE_PLACE_ENUM_DEFS] = []
    defs.enums.group_by { |e| e.group }.each do |name, group|
        group.each do |e|
            subs_data[TEMPLATE_PLACE_ENUM_DEFS] << {name: e.name, value: e.value}
        end
    end

    subs_data[TEMPLATE_PLACE_PROC_DEFS] = []
    defs.procs.each do |p|
        subs_data[TEMPLATE_PLACE_PROC_DEFS] << {name: p.name, name_upper: p.name.upcase, ret_type: p.ret_type,
            params: p.params.map { |p| p.gen_c }.join(', ')}
    end

    subs_data[TEMPLATE_PLACE_EXTENSION_DEFS] = []
    profile.extensions.each do |e|
        subs_data[TEMPLATE_PLACE_EXTENSION_DEFS] << {name: e.name, required: e.required.to_s}
    end

    #TODO: consider API and generator language
    header_template_path = C_GL_HEADER_TEMPLATE_PATH

    out_file << gen_from_template(header_template_path, subs_data)
    return
end

def generate_loader_source(out_dir, profile, defs)
    procs = defs.procs

    out_file = File.open("#{out_dir}/aglet_loader.c", 'w')

    subs_data = {}

    subs_data[TEMPLATE_PLACE_VERSIONS] = []
    defs.versions.each do |v|
        subs_data[TEMPLATE_PLACE_VERSIONS] << {name: v.name, major: v.major, minor: v.minor}
    end

    subs_data[TEMPLATE_PLACE_EXTENSIONS] = []
    profile.extensions.each do |e|
        subs_data[TEMPLATE_PLACE_EXTENSIONS] << {name: e.name, required: e.required.to_s}
    end

    subs_data[TEMPLATE_PLACE_PROCS] = []
    defs.procs.each do |p|
        subs_data[TEMPLATE_PLACE_PROCS] << {name: p.name, name_upper: p.name.upcase}
    end

    #TODO: consider API and generator language
    loader_template_path = C_GL_LOADER_TEMPLATE_PATH

    out_file << gen_from_template(loader_template_path, subs_data)
end

args = parse_args

profile = load_profile(args[:profile])
if profile.nil?
    exit(1)
end

reg_path = GL_REGISTRY_PATH

reg = File.open(reg_path) { |f| Nokogiri::XML(f) }

profile_members = load_profile_members(reg, profile)
if profile_members.nil?
    exit(1)
end

defs = load_gl_defs(reg, profile, profile_members)

out_path = args[:output]
base_header_out_path = "#{out_path}/include"
aglet_header_out_path = "#{base_header_out_path}/aglet"
source_out_path = "#{out_path}/src"

FileUtils.mkdir_p aglet_header_out_path
FileUtils.mkdir_p source_out_path

generate_header(aglet_header_out_path, profile, defs)
generate_loader_source(source_out_path, profile, defs)

khr_header_out_path = "#{base_header_out_path}/KHR"
FileUtils.mkdir_p khr_header_out_path
FileUtils.cp(KHR_HEADER_PATH, "#{khr_header_out_path}/khrplatform.h")
