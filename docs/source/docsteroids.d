import vibe.data.json;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.range;
import std.stdio;
import std.string;
import std.uni;

int main(string[] args)
{
	if( args.length < 3 ){
		writefln("Usage: %s (dst.json) (src.json)\n", args[0]);
		return 1;
	}
	
	auto srctext = readText(args[1]);
	
	int line = 1;
	auto dmd_json = parseJson(srctext, &line);
	
	auto proc = new DocProcessor;
	auto dldoc_json = proc.processProject(dmd_json);
	
	auto dst = appender!string();
	toPrettyJson(dst, dldoc_json);
	std.file.write(args[2], dst.data());
	
	return 0;
}

class DocProcessor {
	private {
		string m_currentModule;
		Json[string] m_dmdModules;
		string[string] m_globalTypeMap; // type name -> module name
		Json[string][string] m_moduleTypeMap; // module name -> (type name -> type def)
	}

	Json processProject(Json project)
	{
		foreach( mod; project )
			m_dmdModules[mod.name.get!string] = mod;

		Json[string] dst;
		foreach( mod; project ){
			dst[mod.name.get!string] = processModule(mod);
		}
		
		Json result = Json(dst);
		
		resolveTypes(result);
		
		return result;
	}
	
	Json processModule(Json mod)
	{
		m_currentModule = mod.name.get!string;
		writefln("Module %s, line %d", mod.name.get!string, mod.line);
		enforce(mod.kind == "module");
		Json dst = Json.EmptyObject;
		dst.kind = "module";
		dst.name = mod.name;
		dst.file = mod.file;
		dst.ddoc = mod.comment;
		dst.members = processMembers(mod.members, "");
		return dst;
	}
	
	void resolveTypes(Json modules)
	{
		void resolveTypesRec(ref Json node, string modname){
			if( node.type == Json.Type.Object && node.kind == "type" ){
				if( "moduleName" in node && node.moduleName.get!string == "" ){
					auto nm = node.name.get!string;
					if( modname in m_moduleTypeMap && nm in m_moduleTypeMap[modname] ){
						node.moduleName = modname;
						node.qualifiedName = modname ~ "." ~ node.nestedName;
					} else if( auto pmn = nm in m_globalTypeMap ){
						node.moduleName = *pmn;
						node.qualifiedName = *pmn ~ "." ~ node.nestedName;
					}
				}
			}
			if( node.type == Json.Type.Object || node.type == Json.Type.Array )
				foreach( ref subnode; node )
					resolveTypesRec(subnode, modname);
		}
		foreach( string mname, ref mod; modules )
			resolveTypesRec(mod, mname);
	}

	Json processMembers(Json members, string sc)
	{
		writefln("Members, line %d", members.line);
		Json[] aliases, functions, constructors, enums, structs, classes, interfaces, variables, templates;

		Json[]* docgrouparr = null;
		Json[] docgroup;
		void add(ref Json[] arr, Json item, Json ddocmem = Json(null))
		{
			auto prot = item.protection.opt!string;
			auto plain_ddoc = ddocmem.type == Json.Type.Null ? item.ddoc.opt!string : ddocmem.comment.opt!string;
			auto ddoc = fullStrip(plain_ddoc);
			bool do_add = prot != "private" && prot != "package" && ddoc != "private";
			bool is_ditto = ddoc == "ditto";

			if( plain_ddoc.length ) item.ddoc = plain_ddoc;


			if( docgroup.length > 0 ){
				if( docgrouparr == &arr && is_ditto && do_add ){
					item.ddoc = docgroup[0].ddoc;
					docgroup ~= item;
					return;
				}
				*docgrouparr ~= Json(docgroup);
			}
			if( do_add ){
				docgroup = [item];
				docgrouparr = &arr;
			} else {
				docgroup = null;
				docgrouparr = null;
			}
		}
		
		foreach( m; members ){
			switch( m.kind.get!string ){
				default: enforce(false, "Unknown module member kind: "~m.kind.get!string); break;
				case "alias": add(aliases, processAlias(m, sc)); break;
				case "constructor": add(constructors, processConstructor(m, sc)); break;
				case "function": add(functions, processFunction(m, sc)); break;
				case "enum": add(enums, processEnum(m, sc)); break;
				case "struct": add(structs, processStruct(m, sc)); break;
				case "class": add(classes, processClass(m, sc)); break;
				case "interface": add(interfaces, processInterface(m, sc)); break;
				case "variable": add(variables, processVariable(m, sc)); break;
				case "template":
					Json repmember;
					if( m.members.length == 1 && m.name.get!string.startsWith(m.members[0].name.get!string) ){
						auto mmem = m.members[0];
						switch( mmem.kind.get!string ){
							default: break;
							case "alias": repmember = processAlias(mmem, sc); add(aliases, repmember, m); break;
							case "constructor": repmember = processConstructor(mmem, sc); add(constructors, repmember, m); break;
							case "function": repmember = processFunction(mmem, sc); add(functions, repmember, m); break;
							case "enum": repmember = processEnum(mmem, sc); add(enums, repmember, m); break;
							case "struct": repmember = processStruct(mmem, sc); add(structs, repmember, m); break;
							case "class": repmember = processClass(mmem, sc); add(classes, repmember, m); break;
							case "interface": repmember = processInterface(mmem, sc); add(interfaces, repmember, m); break;
							case "variable": repmember = processVariable(mmem, sc); add(variables, repmember, m); break;
						}
						// TODO: add template specific stuff to repmember
					}
					
					if( repmember.type != Json.Type.Undefined ){
						repmember.templateName = m.name;
					}
					
					// add generic template as template
					if( repmember.type == Json.Type.Undefined ) add(templates, processTemplate(m, sc));
					break;
			}
		}
		
		if( docgroup.length )
			*docgrouparr ~= Json(docgroup);
		
		Json dst = Json.EmptyObject;
		if( aliases.length ) dst.aliases = aliases;
		if( constructors.length ) dst.constructors = constructors;
		if( functions.length ) dst.functions = functions;
		if( enums.length ) dst.enums = enums;
		if( structs.length ) dst.structs = structs;
		if( classes.length ) dst.classes = classes;
		if( interfaces.length ) dst.interfaces = interfaces;
		if( variables.length ) dst.variables = variables;
		if( templates.length ) dst.templates = templates;

		// perform a (unnecessarily complex) sort of the members
		foreach( ref mgroup; dst ){
			Json*[] items;
			foreach( ref itm; mgroup ) items ~= &itm;
			items.sort!"(*a)[0].nestedName < (*b)[0].nestedName"();
			auto newitems = new Json[items.length];
			foreach(i, itm; items) newitems[i] = *items[i];
			mgroup = Json(newitems);
		}

		return dst;
	}

	Json processAlias(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "alias";
		if( "type" in dst ){
			dst["type"] = processType(al["type"]);
			if( sc.empty ) addType(dst.name.get!string, dst["type"]);
		}
		return dst;
	}

	Json processConstructor(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "constructor";
		dst["type"] = processType(al["type"]);
		return dst;
	}

	Json processFunction(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "function";
		dst["type"] = processType(al["type"]);
		return dst;
	}

	Json processEnum(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "enum";
		dst.baseType = processType(al.base);
		Json[] members;
		foreach( m; al.members ){
			enforce(m.kind == "enum member");
			Json mem = processMember(m, dst.nestedName.get!string);
			mem.kind = "enum member";
			members ~= mem;
		}
		dst.members = Json(members);
		if( sc.empty ) addType(dst.name.get!string, Json.EmptyObject);
		return dst;
	}

	Json processStruct(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "struct";
		if( "members" in al )
			dst.members = processMembers(al.members, dst.nestedName.get!string);
		if( sc.empty ) addType(dst.name.get!string, Json.EmptyObject);
		return dst;
	}

	Json processClass(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "class";
		dst.members = processMembers(al.members, dst.nestedName.get!string);
		dst.base = processType("base" in al ? al.base : Json("Object"));
		Json[] interfaces;
		if( "interfaces" in al ){
			foreach( intf; al.interfaces )
				interfaces ~= processType(intf);
			dst.interfaces = Json(interfaces);
		}
		if( sc.empty ) addType(dst.name.get!string, Json.EmptyObject);
		return dst;
	}

	Json processInterface(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "interface";
		dst.members = processMembers(al.members, dst.nestedName.get!string);
		Json[] interfaces;
		if( "interfaces" in al ){
			foreach( intf; al.interfaces )
				interfaces ~= processType(intf);
			dst.interfaces = Json(interfaces);
		}
		if( sc.empty ) addType(dst.name.get!string, Json.EmptyObject);
		return dst;
	}

	Json processVariable(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "variable";
		if( "type" in al )
			dst["type"] = processType(al["type"]);
		return dst;
	}

	Json processTemplate(Json al, string sc)
	{
		Json dst = processMember(al, sc);
		dst.kind = "template";
		if( "type" in al )
			dst["type"] = processType(al["type"]);
		dst.members = processMembers(al.members, dst.nestedName.get!string);
		return dst;
	}

	Json processMember(Json m, string sc)
	{
		Json dst = Json.EmptyObject;
		dst.name = m.name;
		dst.nestedName = sc.length ? sc ~ "." ~ m.name : m.name;
		writefln("Member %s, line %d", dst.nestedName.get!string, m.line);
		dst.protection = m.protection;
		dst.line = m.line;
		if( "comment" in m )
			dst.ddoc = m.comment;
		return dst;
	}

	enum DeclScope { Global, Parameter, Class }

	Json processType(Json tp, DeclScope sc = DeclScope.Global)
	{
		auto str = tp.get!string;
		auto tokens = tokenizeDSource(str);
		
		auto type = parseTypeDecl(tokens, sc);
		type.text = tp.get!string;
		return type;
	}

	Json parseTypeDecl(ref string[] tokens, DeclScope sc)
	{
		static immutable global_attribute_keywords = ["abstract", "auto", "const", "deprecated", "enum",
			"extern", "final", "immutable", "inout", "shared", "nothrow", "override", "pure",
			"__gshared", "scope", "static", "synchronize"];

		static immutable parameter_attribute_keywords = ["auto", "const", "final", "immutable", "in", "inout",
			"lazy", "out", "ref", "scope", "shared"];

		static immutable member_function_attribute_keywords = ["const", "immutable", "inout", "shared", "pure", "nothrow"];
		
			
		Json[] attributes;	
		if( tokens.length > 0 && tokens[0] == "extern" ){
			enforce(tokens[1] == "(");
			enforce(tokens[3] == ")");
			attributes ~= Json(join(tokens[0 .. 4]));
			tokens = tokens[4 .. $];
		}
		
		immutable string[] attribute_keywords = global_attribute_keywords ~ parameter_attribute_keywords ~ member_function_attribute_keywords;
		/*final switch( sc ){
			case DeclScope.Global: attribute_keywords = global_attribute_keywords; break;
			case DeclScope.Parameter: attribute_keywords = parameter_attribute_keywords; break;
			case DeclScope.Class: attribute_keywords = member_function_attribute_keywords; break;
		}*/

		while( tokens.length > 0 ){
			if( tokens.front == "@" ){
				tokens.popFront();
				attributes ~= Json("@"~tokens.front);
				tokens.popFront();
			} else if( attribute_keywords.countUntil(tokens[0]) >= 0 && tokens[1] != "(" ){
				attributes ~= Json(tokens.front);
				tokens.popFront();
			} else break;
		}

		auto ret = parseType(tokens);
		ret.attributes = Json(attributes);
		return ret;
	}

	Json parseType(ref string[] tokens)
	{
		auto basic_type = parseBasicType(tokens);
		
		while( tokens.length > 0 && (tokens[0] == "function" || tokens[0] == "delegate" || tokens[0] == "(") ){
			Json ret = Json.EmptyObject;
			ret.typeclass = tokens.front == "(" ? "function" : tokens.front;
			ret.returnType = basic_type;
			if( tokens.front != "(" ) tokens.popFront();
			enforce(tokens.front == "(");
			tokens.popFront();
			Json[] params;
			while(true){
				if( tokens.front == ")" ) break;
				enforce(!tokens.empty);
				Json param = Json.EmptyObject;
				param["type"] = parseTypeDecl(tokens, DeclScope.Parameter);
				if( tokens.front != "," && tokens.front != ")" ){
					param.name = tokens.front();
					writefln("got pname %s", tokens.front());
					tokens.popFront();
				}
				if( tokens.front == "..." ){
					param.name = param.name ~ tokens.front;
					tokens.popFront();
				}
				if( tokens.front == "=" ){
					tokens.popFront();
					string defval;
					int ccount = 0;
					while( !tokens.empty ){
						if( ccount == 0 && tokens.front == "," || tokens.front == ")" )
							break;
						if( tokens.front == "(" ) ccount++;
						else if( tokens.front == ")" ) ccount--;
						defval ~= tokens.front;
						tokens.popFront();
					}
					param.defaultValue = defval;
					writefln("got defval %s", param.defaultValue.get!string);
				}
				params ~= param;
				if( tokens.front == ")" ) break;
				enforce(tokens.front == ",", "Expecting ',', got "~tokens.front);
				tokens.popFront();
			}
			tokens.popFront();
			ret.parameters = Json(params);
			basic_type = ret;
		}
		
		return basic_type;	
	}

	Json parseBasicType(ref string[] tokens)
	{
		Json type = Json.EmptyObject;
		{
			static immutable const_modifiers = ["const", "immutable", "shared", "inout"];
			Json[] modifiers;
			while( tokens.length > 2 ){
				if( tokens[1] == "(" && const_modifiers.countUntil(tokens[0]) >= 0 ){
					modifiers ~= Json(tokens[0]);
					tokens.popFrontN(2);
				} else break;
			}
			
			
			if( modifiers.length > 0 ){
				type = parseBasicType(tokens);
				type.modifiers = Json(modifiers);
				foreach( i; 0 .. modifiers.length ){
					//enforce(tokens[i] == ")", "expected ')', got '"~tokens[i]~"'");
					if( tokens[i] == ")" ) // FIXME: this is a hack to make parsing(const(immutable(char)[][]) somehow "work"
						tokens.popFront();
				}
				//tokens.popFrontN(modifiers.length);
			} else {
				size_t i = 0, mod_idx = -2;
				string mod_name;
				string qualified_type_name;
				if( tokens[i] == "." ) i++;
				while( i < tokens.length && isIdent(tokens[i]) ){
					qualified_type_name = join(tokens[0 .. i+1]);
					if( qualified_type_name in m_dmdModules ){
						mod_name = qualified_type_name;
						mod_idx = i;
					}
					i++;
					if( i < tokens.length && tokens[i] == "." ) i++;
					else break;
				}
				string type_name, nested_name;
				if( i == 0 && tokens[0] == "..." ){
					type_name = "...";
					nested_name = null;
				} else if( i == 0 && tokens[0] == "(" ){
					type_name = "constructor";
					nested_name = null;
				} else {
					enforce(i > 0, "Expected identifier but got "~tokens.front);
					type_name = tokens[i-1];
					nested_name = join(tokens[mod_idx+2 .. i]);
					tokens.popFrontN(i);

					if( !tokens.empty && tokens.front == "!" ){
						tokens.popFront();
						if( tokens.front == "(" ){
							size_t j = 1;
							while( j < tokens.length && tokens[j] != ")" ) j++;
							type.templateArgs = join(tokens[0 .. j+1]);
							tokens.popFrontN(j+1);
						} else {
							type.templateArgs = tokens[0];
							tokens.popFront();
						}
					}
				}

				type.kind = "type";
				type.typeClass = "primitive";
				type.qualifiedName = qualified_type_name; // qualified name, as given by dmd
				type.name = type_name; // only the last part of the type name
				type.moduleName = mod_name; // name of the module where the type is declared (empty if in the current module)
				type.nestedName = nested_name; // nested name inside of the module (e.g. ClassName.EnumName)
			}
		}
		
		while( !tokens.empty && tokens.front == "*" ){
			Json ptr = Json.EmptyObject;
			ptr.kind = "type";
			ptr.typeClass = "pointer";
			ptr.elementType = type;
			type = ptr;
			tokens.popFront();
		}

		while( !tokens.empty && tokens.front == "[" ){
			tokens.popFront();
			if( tokens.front == "]" ){
				Json arr = Json.EmptyObject;
				arr.kind = "type";
				arr.typeClass = "array";
				arr.elementType = type;
				type = arr;
			} else if( isDigit(tokens.front[0]) ){
				Json arr = Json.EmptyObject;
				arr.kind = "type";
				arr.typeClass = "static array";
				arr.elementType = type;
				arr.elementCount = to!int(tokens.front);
				tokens.popFront();
				type = arr;
			} else {
				auto keytp = parseType(tokens);
				writefln("GOT TYPE: %s", keytp.toString());
				Json aa = Json.EmptyObject;
				aa.kind = "type";
				aa.typeClass = "associative array";
				aa.elementType = type;
				aa.keyType = keytp;
				type = aa;
			}
			enforce(tokens.front == "]", "Expected '[', got '"~tokens.front~"'.");
			tokens.popFront();
		}
		
		return type;
	}
	
	void addType(string name, Json def)
	{
		m_globalTypeMap[name] = m_currentModule;
		if( m_currentModule !in m_moduleTypeMap ) m_moduleTypeMap[m_currentModule] = null;
		m_moduleTypeMap[m_currentModule][name] = def;
		
	}
}

	string[] tokenizeDSource(string dsource_)
	{
		static immutable dstring[] tokens = [
			"/", "/=", ".", "..", "...", "&", "&=", "&&", "|", "|=", "||",
			"-", "-=", "--", "+", "+=", "++", "<", "<=", "<<", "<<=",
			"<>", "<>=", ">", ">=", ">>=", ">>>=", ">>", ">>>", "!", "!=",
			"!<>", "!<>=", "!<", "!<=", "!>", "!>=", "(", ")", "[", "]",
			"{", "}", "?", ",", ";", ":", "$", "=", "==", "*", "*=",
			"%", "%=", "^", "^=", "~", "~=", "@", "=>", "#"
		];
		static bool[dstring] token_map;
		
		if( !token_map.length ){
			foreach( t; tokens )
				token_map[t] = true;
			token_map.rehash;
		}
		
		dstring dsource = to!dstring(dsource_);
		
		dstring[] ret;
		outer:
		while(true){
			dsource = stripLeft(dsource);
			if( dsource.length == 0 ) break;
			
			// special token?
			foreach_reverse( i; 1 .. min(5, dsource.length+1) )
				if( dsource[0 .. i] in token_map ){
					ret ~= dsource[0 .. i];
					dsource.popFrontN(i);
					continue outer;
				}
			
			// identifier?
			if( dsource[0] == '_' || std.uni.isAlpha(dsource[0]) ){
				size_t i = 1;
				while( i < dsource.length && (dsource[i] == '_' || std.uni.isAlpha(dsource[i]) || isDigit(dsource[i])) ) i++;
				ret ~= dsource[0 .. i];
				dsource.popFrontN(i);
				continue;
			}
			
			// character literal?
			if( dsource[0] == '\'' ){
				assert(false);
			}
			
			// string? (incomplete!)
			if( dsource[0] == '"' ){
				size_t i = 1;
				while( dsource[i] != '"' ){
					i++;
					enforce(i < dsource.length);
				}
				ret ~= dsource[1 .. i+1];
				dsource.popFrontN(i+1);
			}
			
			// number?
			if( isDigit(dsource[0]) || dsource[0] == '.' ){
				assert(isDigit(dsource[0]));
				size_t i = 1;
				while( i < dsource.length && isDigit(dsource[i]) ) i++;
				assert(i >= dsource.length || dsource[i] != '.' && dsource[i] != 'e' && dsource[i] != 'E');
				// only integers supported any badly supported
				ret ~= dsource[0 .. i];
				dsource.popFrontN(i);
				if( dsource.startsWith("u") ) dsource.popFront();
			}
			
			ret ~= dsource[0 .. 1];
			dsource.popFront();
		}
		
		auto ret_ = new string[ret.length];
		foreach( i; 0 .. ret.length ) ret_[i] = to!string(ret[i]);
		return ret_;
	}

bool isDigit(dchar ch)
{
	return ch >= '0' && ch <= '9';
}

bool isIdent(string str)
{
	if( str.length < 1 ) return false;
	foreach( i, dchar ch; str ){
		if( ch == '_' || std.uni.isAlpha(ch) ) continue;
		if( i > 0 && isDigit(ch) ) continue;
		return false;
	}
	return true;	
}

string fullStrip(string s)
{
	string chars = " \t\r\n";
	while( s.length > 0 && chars.countUntil(s[0]) >= 0 ) s.popFront();
	while( s.length > 0 && chars.countUntil(s[$-1]) >= 0 ) s.popBack();
	return s;
}