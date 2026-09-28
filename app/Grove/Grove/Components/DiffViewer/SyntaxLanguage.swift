// Components/DiffViewer/SyntaxLanguage.swift
// Grove
//
// Just enough of each common language's lexical rules to color keywords, strings, comments and numbers.

import Foundation

struct SyntaxLanguage: Sendable {
    let name: String
    let keywords: Set<String>
    let lineComments: [String]
    let blockComment: (open: String, close: String)?
    let quotes: Set<Character>
    /// Delimiters of strings that can span lines, e.g. `"""`.
    let multilineQuotes: [String]
    /// Capitalized identifiers read as types, which holds in C-family languages and Python but not in shell or SQL.
    let capitalizedTypes: Bool
    var caseInsensitiveKeywords = false

    static func forPath(_ path: String) -> SyntaxLanguage? {
        let name = (path as NSString).lastPathComponent
        if let language = byFileName[name] { return language }
        return byExtension[(name as NSString).pathExtension.lowercased()]
    }

    private static let byFileName: [String: SyntaxLanguage] = [
        "Podfile": .ruby, "Gemfile": .ruby, "Fastfile": .ruby, "Rakefile": .ruby, "Appfile": .ruby, "Matchfile": .ruby,
        "Dockerfile": .shell, "Makefile": .shell, ".zshrc": .shell, ".bashrc": .shell
    ]

    private static let byExtension: [String: SyntaxLanguage] = {
        var map: [String: SyntaxLanguage] = [:]
        let groups: [([String], SyntaxLanguage)] = [
            (["swift"], .swift),
            (["c", "h", "m", "mm", "cc", "cpp", "cxx", "hpp", "hh"], .cFamily),
            (["js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts"], .javaScript),
            (["py", "pyi"], .python),
            (["rb", "rake", "gemspec", "podspec"], .ruby),
            (["go"], .go),
            (["rs"], .rust),
            (["java", "kt", "kts", "scala", "groovy", "gradle", "dart"], .jvm),
            (["cs"], .cSharp),
            (["sh", "bash", "zsh", "fish", "command"], .shell),
            (["json", "jsonc"], .json),
            (["yml", "yaml", "toml"], .yaml),
            (["css", "scss", "less"], .css),
            (["sql"], .sql),
            (["php"], .php)
        ]
        for (extensions, language) in groups {
            for ext in extensions { map[ext] = language }
        }
        return map
    }()
}

// MARK: - Languages

extension SyntaxLanguage {

    private static func words(_ text: String) -> Set<String> {
        Set(text.split(separator: " ").map(String.init))
    }

    static let swift = SyntaxLanguage(
        name: "Swift",
        keywords: words("""
            associatedtype actor async await break case catch class continue default defer deinit do else enum \
            extension fallthrough false fileprivate final for func guard if import in indirect init inout internal \
            is lazy let mutating nil nonisolated open operator override private protocol public repeat rethrows \
            return self Self some any static struct subscript super switch throw throws true try typealias var weak \
            where while unowned convenience dynamic required optional consuming borrowing sending
            """),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\""], multilineQuotes: ["\"\"\""],
        capitalizedTypes: true)

    static let cFamily = SyntaxLanguage(
        name: "C",
        keywords: words("""
            auto break case char const continue default do double else enum extern float for goto if inline int \
            long register return short signed sizeof static struct switch typedef union unsigned void volatile while \
            bool true false NULL nullptr class namespace template typename public private protected virtual override \
            new delete this using try catch throw constexpr noexcept operator friend explicit mutable const_cast \
            static_cast dynamic_cast reinterpret_cast @interface @implementation @end @property @protocol @class \
            @selector @synthesize self super nil YES NO id instancetype nonatomic strong weak assign copy readonly
            """),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: [],
        capitalizedTypes: true)

    static let javaScript = SyntaxLanguage(
        name: "JavaScript",
        keywords: words("""
            abstract as async await break case catch class const constructor continue debugger declare default \
            delete do else enum export extends false finally for from function get if implements import in \
            instanceof interface keyof let module namespace new null of private protected public readonly return \
            satisfies set static super switch this throw true try type typeof undefined var void while with yield
            """),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: ["`"],
        capitalizedTypes: true)

    static let python = SyntaxLanguage(
        name: "Python",
        keywords: words("""
            False None True and as assert async await break class continue def del elif else except finally for \
            from global if import in is lambda match case nonlocal not or pass raise return self try while with yield
            """),
        lineComments: ["#"], blockComment: nil, quotes: ["\"", "'"], multilineQuotes: ["\"\"\"", "'''"],
        capitalizedTypes: true)

    static let ruby = SyntaxLanguage(
        name: "Ruby",
        keywords: words("""
            BEGIN END alias and begin break case class def defined? do else elsif end ensure false for if in module \
            next nil not or redo rescue retry return self super then true undef unless until when while yield \
            require require_relative attr_reader attr_writer attr_accessor private protected public lambda proc
            """),
        lineComments: ["#"], blockComment: ("=begin", "=end"), quotes: ["\"", "'"], multilineQuotes: [],
        capitalizedTypes: true)

    static let go = SyntaxLanguage(
        name: "Go",
        keywords: words("""
            break case chan const continue default defer else fallthrough for func go goto if import interface map \
            package range return select struct switch type var true false nil iota any error string int int64 bool \
            byte rune float64 uint make new len cap append panic recover
            """),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: ["`"],
        capitalizedTypes: false)

    static let rust = SyntaxLanguage(
        name: "Rust",
        keywords: words("""
            as async await break const continue crate dyn else enum extern false fn for if impl in let loop match \
            mod move mut pub ref return self Self static struct super trait true type unsafe use where while
            """),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\""], multilineQuotes: [],
        capitalizedTypes: true)

    static let jvm = SyntaxLanguage(
        name: "Java",
        keywords: words("""
            abstract assert boolean break byte case catch char class const continue default do double else enum \
            extends final finally float for if implements import instanceof int interface long native new package \
            private protected public return short static super switch synchronized this throw throws transient try \
            void volatile while true false null var val fun object companion data sealed override open internal \
            when is in out lateinit suspend init typealias def
            """),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: ["\"\"\""],
        capitalizedTypes: true)

    static let cSharp = SyntaxLanguage(
        name: "C#",
        keywords: words("""
            abstract as async await base bool break byte case catch char class const continue decimal default \
            delegate do double else enum event explicit extern false finally float for foreach get if implicit in \
            int interface internal is lock long namespace new null object operator out override params private \
            protected public readonly record ref return sealed set short static string struct switch this throw true \
            try typeof uint using var virtual void while yield
            """),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: [],
        capitalizedTypes: true)

    static let shell = SyntaxLanguage(
        name: "Shell",
        keywords: words("""
            if then else elif fi case esac for select while until do done in function return local export readonly \
            unset set shift exit source alias echo cd FROM RUN CMD COPY ADD ENV ARG WORKDIR ENTRYPOINT EXPOSE USER
            """),
        lineComments: ["#"], blockComment: nil, quotes: ["\"", "'"], multilineQuotes: [],
        capitalizedTypes: false)

    static let json = SyntaxLanguage(
        name: "JSON", keywords: words("true false null"), lineComments: ["//"], blockComment: ("/*", "*/"),
        quotes: ["\""], multilineQuotes: [], capitalizedTypes: false)

    static let yaml = SyntaxLanguage(
        name: "YAML", keywords: words("true false null yes no on off"), lineComments: ["#"], blockComment: nil,
        quotes: ["\"", "'"], multilineQuotes: [], capitalizedTypes: false)

    static let css = SyntaxLanguage(
        name: "CSS",
        keywords: words("@media @import @include @mixin @extend @keyframes @font-face !important inherit initial none auto"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: [],
        capitalizedTypes: false)

    static let sql = SyntaxLanguage(
        name: "SQL",
        keywords: words("""
            select from where insert into values update set delete create table alter drop index view join left \
            right inner outer on and or not null is as order by group having limit offset primary key foreign \
            references default unique distinct union all case when then else end begin commit rollback
            """),
        lineComments: ["--"], blockComment: ("/*", "*/"), quotes: ["'", "\""], multilineQuotes: [],
        capitalizedTypes: false, caseInsensitiveKeywords: true)

    static let php = SyntaxLanguage(
        name: "PHP",
        keywords: words("""
            abstract and array as break case catch class clone const continue declare default do echo else elseif \
            empty endif endforeach extends final finally fn for foreach function global if implements include \
            instanceof interface isset list match namespace new null or print private protected public readonly \
            require return static switch this throw trait true false try unset use var while yield
            """),
        lineComments: ["//", "#"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], multilineQuotes: [],
        capitalizedTypes: true)
}
