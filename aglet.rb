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

LANGUAGE_C = 'c'
LANGUAGE_RUST = 'rust'

API_GL = 'gl'
API_GL_CORE = 'glcore'
API_GLES = 'gles'
API_GLSC = 'glsc'

FEATURE_API_GL = 'gl'
FEATURE_API_GLES_1 = 'gles1'
FEATURE_API_GLES_2 = 'gles2'
FEATURE_API_GLSC_2 = 'glsc2'

API_FAMILY_GL = 'gl'

API_FRIENDLY_GL = 'GL'
API_FRIENDLY_GLES = 'GL ES'
API_FRIENDLY_GLSC = 'GL SC'

TEMPLATE_PLACE_GLOBAL_API_NAME = 'api_name'
TEMPLATE_PLACE_GLOBAL_MIN_API_VERSION = 'min_api_version'
TEMPLATE_PLACE_GLOBAL_MIN_API_VERSION_MAJOR = 'min_api_version_major'
TEMPLATE_PLACE_GLOBAL_MIN_API_VERSION_MINOR = 'min_api_version_minor'
TEMPLATE_PLACE_GLOBAL_TARGET_API_VERSION = 'target_api_version'
TEMPLATE_PLACE_GLOBAL_TARGET_API_VERSION_MAJOR = 'target_api_version_major'
TEMPLATE_PLACE_GLOBAL_TARGET_API_VERSION_MINOR = 'target_api_version_minor'

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

RUST_TEMPLATES_PATH = "#{__dir__}/templates/rust"
RUST_GL_TEMPLATES_PATH = "#{RUST_TEMPLATES_PATH}/gl"
RUST_GL_LOADER_TEMPLATE_PATH = "#{RUST_GL_TEMPLATES_PATH}/aglet.rs"

HEADER_FILE_NAMES = { LANGUAGE_C => 'aglet.h' }
SOURCE_FILE_NAMES = { LANGUAGE_C => 'aglet_loader.c', LANGUAGE_RUST => 'aglet.rs' }

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

    def gen_rust()
        if @name == 'type'
            rust_name = 'ty'
        elsif @name == 'ref'
            rust_name = 'reference'
        else
            rust_name = @name
        end

        rust_type = transform_c_type_for_rust(@type)

        return "#{rust_name}: #{rust_type}"
    end

    def gen_names_c()
        return "#{@name}"
    end

    def gen_names_rust()
        if @name == 'type'
            return 'ty'
        elsif @name == 'ref'
            return 'reference'
        else
            return @name
        end
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
    def initialize(name, group, value, width)
        @name = name
        @group = group
        @value = value
        @width = width
    end
    attr_reader :name
    attr_reader :group
    attr_reader :value
    attr_reader :width
end

class ApiDefs
    def initialize(min_version, versions, types, enums, procs)
        @min_version = min_version
        @versions = versions
        @types = types
        @enums = enums
        @procs = procs
    end
    attr_reader :min_version
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
    def initialize(api, feature_api, api_family, min_version, target_version, extensions)
        @api = api
        @feature_api = feature_api
        @api_family = api_family
        @min_version = min_version
        @target_version = target_version
        @extensions = extensions
    end
    attr_reader :api
    attr_reader :feature_api
    attr_reader :api_family
    attr_reader :min_version
    attr_reader :target_version
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

def transform_c_type_for_rust(c_type)
    if c_type == 'void'
        return '()'
    end

    if c_type.count('*') == 0
        return c_type.strip()
    end

    bare_type = c_type.gsub(/\bconst\b|\*/, '').strip()
    if bare_type == 'void'
        bare_type = 'std::ffi::c_void'
    end

    if c_type.count('*') == 1
        if c_type.start_with?('const ')
            rust_type = "*const #{bare_type}"
        else
            rust_type = "*mut #{bare_type}"
        end
    elsif c_type.count('*') == 2
        if c_type.start_with?('const ')
            inner_ptr_type = '*const'
        else
            inner_ptr_type = '*mut'
        end

        inner_segment = c_type.gsub(/ *\* *$/, '')
        if inner_segment.end_with?('const')
            outer_ptr_type = '*const'
        else
            outer_ptr_type = '*mut'
        end

        rust_type = "#{outer_ptr_type} #{inner_ptr_type} #{bare_type}"
    end
end

def gen_from_template(template_path, subst_map)
    template_content = File.read template_path
    interim_content = ''

    last_off = 0

    sec_if_templates = template_content.to_enum(:scan, /(?<start>[ \t]*#)\= if (?<expr>.*?) \=#\n(?<content>.*?)\n[ \t]*#\= \/if \=#(?<end>\n)/m).map { Regexp.last_match }
    sec_if_templates.each do |s|
        sec_start = s.offset(:start)[0] - 1
        sec_end = s.end(:end)

        interim_content << template_content[last_off..sec_start]
        last_off = sec_end

        sec_expr = s.named_captures['expr']

        subst_expr = sec_expr.dup
        subst_map.each do |sub_item|
            next unless sub_item[1].is_a?(String) or sub_item[1].is_a?(Numeric)

            subst_expr.gsub! "@{#{sub_item[0]}}", sub_item[1].to_s
        end

        expr_res = eval(subst_expr)
        next unless expr_res

        interim_content << s.named_captures['content']
    end

    interim_content << template_content[last_off..]

    template_content = interim_content.dup
    interim_content = ''
    last_off = 0

    sec_foreach_templates = template_content.to_enum(:scan, /(?<start>[ \t]*#)\= foreach (?<name>.*?) \=#\n(?<content>.*?)\n[ \t]*#\= \/foreach \=#(?<end>\n)/m).map { Regexp.last_match }
    sec_foreach_templates.each do |s|
        sec_start = s.offset(:start)[0] - 1
        sec_end = s.end(:end)

        interim_content << template_content[last_off..sec_start]
        last_off = sec_end

        sec_name = s.named_captures['name']
        sec_content = s.named_captures['content']
        sec_subs = subst_map[sec_name]
        next unless sec_subs.is_a? Array

        sec_output = ''

        sec_subs.each do |sub_group|
            cur_content = sec_content.dup
            sub_group.each do |sub_item|
                cur_content.gsub! "@{#{sub_item[0]}}", sub_item[1].to_s
            end

            sec_output << "#{cur_content}\n"
        end

        interim_content << sec_output
    end

    interim_content << template_content[last_off..]

    final_content = interim_content

    subst_map.each do |sub_item|
        next unless sub_item[1].is_a?(String) or sub_item[1].is_a?(Numeric)
        final_content.gsub! "@{#{sub_item[0]}}", sub_item[1].to_s
    end

    return final_content
end

def params_to_str(lang, params)
    if lang == 'c'
        if params.empty?
            return 'void'
        else
            return params.map { |p| p.gen_c }.join(', ')
        end
    elsif lang == 'rust'
        if params.empty?
            return ''
        else
            return params.map { |p| p.gen_rust }.join(', ')
        end
    else
        raise "Invalid output language '#{lang}'"
    end
end

def param_names_to_str(lang, params)
    if lang == 'c'
        if params.empty?
            return 'void'
        else
            return params.map { |p| p.gen_names_c }.join(', ')
        end
    elsif lang == 'rust'
        if params.empty?
            return ''
        else
            return params.map { |p| p.gen_names_rust }.join(', ')
        end
    else
        raise "Invalid output language '#{lang}'"
    end
end


def parse_args()
    options = {}
    OptionParser.new do |opts|
        opts.banner = "Usage: aglet.rb -l <language> -p <profile> -o <output dir>"

        opts.on('-l LANGUAGE', '--lang=LANGUAGE', 'Language to emit bindings for') do |l|
            options[:language] = l.downcase()
        end
        opts.on('-p PROFILE', '--profile=PROFILE', 'Path to profile file') do |p|
            options[:profile] = p
        end
        opts.on('-o OUTPUT', '--output=OUTPUT', 'Path to output directory') do |h|
            options[:output] = h
        end
    end.parse!

    raise "Output language is required" unless options[:language]
    raise "Profile path is required" unless options[:profile]
    raise "Output path is required" unless options[:output]

    options
end

def version_eq(l_major, l_minor, r_major, r_minor)
    l_major == r_major and l_minor == r_minor
end

def version_lt(l_major, l_minor, r_major, r_minor)
    l_major < r_major or (l_major == r_major and l_minor < r_minor)
end

def version_lte(l_major, l_minor, r_major, r_minor)
    l_major < r_major or (l_major == r_major and l_minor <= r_minor)
end

def version_gt(l_major, l_minor, r_major, r_minor)
    l_major > r_major or (l_major == r_major and l_minor > r_minor)
end

def version_gte(l_major, l_minor, r_major, r_minor)
    l_major > r_major or (l_major == r_major and l_minor >= r_minor)
end

def api_to_friendly_name(api)
    return API_FRIENDLY_GL if api == API_GL or api == API_GL_CORE
    return API_FRIENDLY_GLES if api == API_GLES
    return API_FRIENDLY_GLSC if api == API_GLSC
end

def load_profile(profile_path)
    profile = File.open(profile_path) { |f| Nokogiri::XML(f) }
    api = profile.xpath('/profile/api/name/text()').text
    min_version = profile.xpath('/profile/api/minVersion/text()').text
    target_version = profile.xpath('/profile/api/targetVersion/text()').text

    raise "Minimum version is malformed for API '#{api}'" unless min_version.include? '.'

    raise "Target version is malformed for API '#{api}'" unless target_version.include? '.'

    min_major, min_minor = min_version.split('.').map(&:to_i)

    target_major, target_minor = target_version.split('.').map(&:to_i)

    feature_api = ''
    api_family = ''
    if api == API_GL_CORE or api == API_GL
        feature_api = FEATURE_API_GL
        api_family = API_FAMILY_GL
    elsif api == API_GLES
        if target_major == 1
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

    # some tricky rules to handle here

    raise 'Minimum API version must be less than or equal to target version' if version_gt(min_major, min_minor, target_major, target_minor)

    # GLES 1.x and 2.x/3.x are effectively considered different APIs by the
    # spec, so it doesn't make sense to target both at once
    raise 'Minimum GLES version must be >= 2.0 when version 2/3 is targeted' if api == API_GLES and target_major >= 2 and min_major < 2

    raise 'Target GL version must be >= 3.2 when core profile is specified' if api == API_GL_CORE and version_lt(target_major, target_minor, 3, 2)

    raise 'Minimum GL version must be >= 3.2 when core profile is specified' if api == API_GL_CORE and version_lt(min_major, min_minor, 3, 2)

    extensions = profile.xpath('/profile/extensions/extension')
        .map { |e| ApiExtension.new(e.text, e.at_xpath('./@required').to_s.downcase == 'true') }

    return ApiProfile.new(api, feature_api, api_family, min_version, target_version, extensions)
end

def load_profile_members(reg, profile)
    require_types = []
    require_enums = []
    require_procs = []

    min_major, min_minor = profile.min_version.split('.').map(&:to_i)
    target_major, target_minor = profile.target_version.split('.').map(&:to_i)

    seen_vers = 0
    gl_feature_spec = reg.xpath('/registry/feature[@api="%s"]' % profile.feature_api)
    gl_feature_spec.each do |ver|
        feature_number = ver.xpath('@number').text
        feature_major, feature_minor = feature_number.split('.').map(&:to_i)
        next if version_gt(feature_major, feature_minor, target_major, target_minor)

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

        require_types += require_secs.xpath('./type/@name').map { |n| n.text }.flatten
        require_enums += require_secs.xpath('./enum/@name').map { |n| n.text }.flatten
        require_procs += require_secs.xpath('./command/@name').map { |n| n.text }.flatten

        require_types -= remove_secs.xpath('./type/@name').map { |n| n.text }.flatten
        require_enums -= remove_secs.xpath('./enum/@name').map { |n| n.text }.flatten
        require_procs -= remove_secs.xpath('./command/@name').map { |n| n.text }.flatten
    end

    if seen_vers == 0
        print "Requested profile does not seem to include any defined versions\n"
        return nil
    end

    ext_names = profile.extensions.map { |e| e.name }

    ext_names.each do |ext_name|
        ext = reg.xpath("/registry/extensions/extension[@name='#{ext_name}']")
        if ext == nil or ext.empty?
            raise "Extension #{ext_name} could not be found"
        end

        supported = ext.xpath('@supported').text
        if supported != nil and not supported.split('|').include? profile.api
            raise "Extension #{ext_name} is not supported by the selected API (#{profile.api})"
        end

        if profile.feature_api == FEATURE_API_GL
            if profile.api == API_GL_CORE
                require_secs = ext.xpath("./require[not(@api) or (@api='#{profile.feature_api}' and @profile='core')]")
            else profile.api == API_GL
                require_secs = ext.xpath("./require[not(@api) or (@api='#{profile.feature_api}' and @profile='compatibility')]")
            end
        else
            require_secs = ext.css("./require[not(@api) or @api='#{profile.feature_api}']")
        end

        require_types += require_secs.xpath("./type/@name").map { |n| n.text }.flatten
        require_enums += require_secs.xpath("./enum/@name").map { |n| n.text }.flatten
        require_procs += require_secs.xpath("./command/@name").map { |n| n.text }.flatten
    end

    print "Finished discovering members for profile \"#{profile.api} #{profile.target_version}\""
    print " (#{require_types.length} types, #{require_enums.length} enums, #{require_procs.length} functions)\n"

    return ApiMembers.new(require_types.to_set, require_enums.to_set, require_procs.to_set)
end

def parse_param_type(raw)
    raw.gsub(/<name>.*<\/name>/, '').gsub(/<\/?ptype>/, '').gsub('* ', ' *')
end

def load_gl_defs(reg, profile, members)
    min_version = nil
    versions = []
    types = []
    enums = []
    procs = []

    gl_feature_spec = reg.xpath('/registry/feature[@api="%s"]' % profile.feature_api)
    gl_feature_spec.each do |ver|
        feature_number = ver.xpath('@number').text
        feature_name = ver.xpath('@name').text
        feature_major, feature_minor = feature_number.split('.').map(&:to_i)
        versions << ApiVersion.new(profile.feature_api, feature_name, feature_major, feature_minor)
    end

    req_procs = members.proc_names

    extra_types = Set[]

    # discover commands first because they can implicitly require extra types
    reg.xpath('/registry/commands/command').each do |cmd_root|
        cmd_name = cmd_root.xpath('./proto/name')

        next unless req_procs.include? cmd_name.text

        name = cmd_name.text.strip

        proto = cmd_root.xpath('./proto')
        ret = parse_param_type proto.inner_html
        ret.gsub!(' *', '* ')
        ret.strip!

        if ptype = proto.at_xpath('./ptype')
            extra_types << ptype.text
        end

        params = []

        cmd_root.xpath('./param').each do |cmd_param|
            if ptype = cmd_param.at_xpath('./ptype')
                extra_types << ptype.text
            end

            param_name = cmd_param.xpath('./name').text
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

    reg.xpath('/registry/types/type').each do |type_root|
        next if name_attr = type_root.at_xpath('./@name') and
            (name_attr.text == 'khrplatform' or
                (profile.api_family == API_FAMILY_GL and name_attr.text == 'GLhandleARB'))

        type_name = type_root.xpath('./name').text
        next unless req_types.include? type_name
        # bad idea to parse XML with regex, but this is extremely domain-specific
        type_typedef = type_root.to_s.gsub('<apientry/>', 'APIENTRY').gsub(/<.*?>/, '')

        types << ApiType.new(type_name, type_typedef)
    end

    reg.xpath('/registry/enums/enum').each do |enum_root|
        enum_name = enum_root.xpath('./@name').text
        enum_group = enum_root.xpath('./@group').text
        enum_value = enum_root.xpath('./@value').text
        enum_type = enum_root.xpath('./@type').text
        next if enum_api = enum_root.at_xpath('./@api') and enum_api != profile.feature_api
        next unless members.enum_names.include? enum_name

        if enum_type == 'ull'
            enum_width = 64
        else
            enum_width = 32
        end

        enums << ApiEnum.new(enum_name, enum_group, enum_value, enum_width)
    end

    min_major, min_minor = profile.min_version.split('.').map(&:to_i)
    min_version = versions.find { |v| version_eq(v.major, v.minor, min_major, min_minor) }

    raise "Minimum API version #{profile.min_version} not found in registry" if min_version.nil?

    ApiDefs.new(min_version, versions, types, enums, procs)
end

def gen_subst_map(lang, profile, defs)
    subst_map = {}

    min_major, min_minor = profile.min_version.split('.').map(&:to_i)
    target_major, target_minor = profile.target_version.split('.').map(&:to_i)

    subst_map[TEMPLATE_PLACE_GLOBAL_API_NAME] = api_to_friendly_name profile.api
    subst_map[TEMPLATE_PLACE_GLOBAL_MIN_API_VERSION] = defs.min_version.name
    subst_map[TEMPLATE_PLACE_GLOBAL_MIN_API_VERSION_MAJOR] = min_major
    subst_map[TEMPLATE_PLACE_GLOBAL_MIN_API_VERSION_MINOR] = min_minor
    subst_map[TEMPLATE_PLACE_GLOBAL_TARGET_API_VERSION] = profile.target_version
    subst_map[TEMPLATE_PLACE_GLOBAL_TARGET_API_VERSION_MAJOR] = target_major
    subst_map[TEMPLATE_PLACE_GLOBAL_TARGET_API_VERSION_MINOR] = target_minor

    subst_map[TEMPLATE_PLACE_VERSIONS] = []
    defs.versions.each do |v|
        subst_map[TEMPLATE_PLACE_VERSIONS] << {name: v.name, name_lower: v.name.downcase(),
            major: v.major, minor: v.minor}
    end

    subst_map[TEMPLATE_PLACE_EXTENSION_DEFS] = []
    profile.extensions.each do |e|
        subst_map[TEMPLATE_PLACE_EXTENSION_DEFS] << {name: e.name, name_lower: e.name.downcase(),
            required: e.required.to_s}
    end

    subst_map[TEMPLATE_PLACE_TYPE_DEFS] = []
    defs.types.each do |t|
        subst_map[TEMPLATE_PLACE_TYPE_DEFS] << {name: t.name, typedef: t.typedef}
    end

    subst_map[TEMPLATE_PLACE_ENUM_DEFS] = []
    defs.enums.group_by { |e| e.group }.each do |name, group|
        group.each do |e|
            subst_map[TEMPLATE_PLACE_ENUM_DEFS] << {name: e.name, value: e.value, width: e.width}
        end
    end

    subst_map[TEMPLATE_PLACE_PROC_DEFS] = []
    defs.procs.each do |p|
        if lang == 'rust'
            ret_type = transform_c_type_for_rust(p.ret_type)
        else
            ret_type = p.ret_type
        end

        subst_map[TEMPLATE_PLACE_PROC_DEFS] << {name: p.name, name_upper: p.name.upcase, ret_type: ret_type,
            params: params_to_str(lang, p.params), param_names: param_names_to_str(lang, p.params) }
    end

    subst_map[TEMPLATE_PLACE_EXTENSIONS] = []
    profile.extensions.each do |e|
        subst_map[TEMPLATE_PLACE_EXTENSIONS] << {name: e.name, name_lower: e.name.downcase(),
            required: e.required.to_s}
    end

    subst_map[TEMPLATE_PLACE_PROCS] = []
    defs.procs.each do |p|
        subst_map[TEMPLATE_PLACE_PROCS] << {name: p.name, name_upper: p.name.upcase}
    end

    return subst_map
end

def generate_header(lang, out_dir, profile, defs)
    # rust doesn't separate declarations from definitions
    return if lang == LANGUAGE_RUST

    out_file = File.open("#{out_dir}/#{HEADER_FILE_NAMES[lang]}", 'w')

    subst_map = gen_subst_map(lang, profile, defs)

    if lang == LANGUAGE_C
        header_template_path = C_GL_HEADER_TEMPLATE_PATH
    else
        raise "Invalid output language '#{lang}'"
    end

    out_file << gen_from_template(header_template_path, subst_map)
    return
end

def generate_loader_source(lang, out_dir, profile, defs)
    procs = defs.procs

    out_file = File.open("#{out_dir}/#{SOURCE_FILE_NAMES[lang]}", 'w')

    subst_map = gen_subst_map(lang, profile, defs)

    if lang == LANGUAGE_C
        loader_template_path = C_GL_LOADER_TEMPLATE_PATH
    elsif lang == LANGUAGE_RUST
        loader_template_path = RUST_GL_LOADER_TEMPLATE_PATH
    else
        raise "Invalid output language '#{lang}'"
    end

    out_file << gen_from_template(loader_template_path, subst_map)
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

lang = args[:language]

out_path = args[:output]
base_header_out_path = "#{out_path}/include"
aglet_header_out_path = "#{base_header_out_path}/aglet"
source_out_path = "#{out_path}/src"

FileUtils.mkdir_p aglet_header_out_path
FileUtils.mkdir_p source_out_path

generate_header(lang, aglet_header_out_path, profile, defs)
generate_loader_source(lang, source_out_path, profile, defs)

khr_header_out_path = "#{base_header_out_path}/KHR"
FileUtils.mkdir_p khr_header_out_path
FileUtils.cp(KHR_HEADER_PATH, "#{khr_header_out_path}/khrplatform.h")
