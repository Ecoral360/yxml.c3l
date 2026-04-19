module std::encoding::xml;
import std::encoding::xml::dom;
import std::collections, std::io;

<*
XML 1.0 parser and writer based on yxml <https://dev.yorhel.nl/yxml>

A native port of the yxml C library. It provides a low-level streaming
parser (XmlReader) and a high-level DOM API (XmlDocument).

Parser Characteristics:
- Non-validating: Checks syntax/nesting but ignores DTD/Schema rules.
- Byte-oriented: State-machine based, buffer-less design.
- No core malloc: The internal engine requires no heap allocation.
- ASCII-compatible: Works with UTF-8, ISO-8859-1, etc.

What it DOES NOT do (Limitations):
- No DTD/Schema validation.
- No custom entity references (only standard &amp;, &lt;, etc.).
- No namespace assistance (prefixes are kept in the name).
- No XPath or XSLT.
- No verification of Unicode ranges (assumes valid input).
- No attribute uniqueness checks.
- No household chores.

API & Implementation:
- XmlReader: Low-level streaming parser that works with any InStream.
- XmlWriter: XML serializer that integrates with any OutStream.
- XmlDocument: High-level DOM API for loading, searching, and modifying XML.
- Internal: The `internal::Parser` contains the core ported state-machine.

Examples: https://github.com/c3lang/c3c/tree/master/resources/examples/xml/
*>

faultdef XML_SYNTAX, XML_STACK_OVERFLOW, XML_TAG_MISMATCH, XML_INVALID_REF;

enum XmlEventKind
{
	START_ELEMENT,
	END_ELEMENT,
	ATTRIBUTE,
	TEXT,
	PI,
	COMMENT
}

struct XmlEvent
{
	XmlEventKind kind;
	String name;
	String value;
}

<* Loads and parses an XML document from a stream into a DOM tree. *>
fn XmlDocument*? load(Allocator allocator, InStream stream)
{
	XmlReader reader;
	char[4096] stack;
	reader.init(stream, &stack[0], (usz)stack.len, allocator)!;
	defer reader.destroy();

	XmlDocument* document = alloc::new(allocator, XmlDocument);
	document.allocator = allocator;

	XmlNode* root = null;
	XmlNode* current = null;
	List{XmlNode*} node_stack;
	node_stack.init(allocator);
	defer node_stack.free();

	while (true)
	{
		XmlEvent? event_opt = reader.next_event();
		if (catch err = event_opt)
		{
			if (err == io::EOF) break;
			if (root)
			{
				root.free(allocator);
				alloc::free(allocator, root);
			}
			alloc::free(allocator, document);
			return err~;
		}
		XmlEvent event = event_opt;

		switch (event.kind)
		{
			case START_ELEMENT:
				XmlNode* node = alloc::new(allocator, XmlNode);
				*node = { .kind = START_ELEMENT, .name = event.name.copy(allocator), .doc = document };
				node.attributes.init(allocator);
				node.children.init(allocator);

				if (current)
				{
					current.children.push(node);
				}
				else
				{
					root = node;
				}

				node_stack.push(current);
				current = node;

			case END_ELEMENT:
				if (!current) return XML_TAG_MISMATCH~;
				current = node_stack.pop()!!;

			case ATTRIBUTE:
				if (!current) return XML_SYNTAX~;
				current.attributes.set(event.name, event.value.copy(allocator));

			case TEXT:
				XmlNode* node = alloc::new(allocator, XmlNode);
				*node = { .kind = TEXT, .value = event.value.copy(allocator), .doc = document };
				node.attributes.init(allocator);
				node.children.init(allocator);
				if (current)
				{
					current.children.push(node);
				}
				else if (!root)
				{
					// Allow top-level text as a fallback root (Standard XML requires a root element).
					root = node;
				}

			case PI:
				XmlNode* node = alloc::new(allocator, XmlNode);
				*node = { .kind = PI, .name = event.name.copy(allocator), .value = event.value.copy(allocator), .doc = document };
				node.attributes.init(allocator);
				node.children.init(allocator);
				if (current)
				{
					current.children.push(node);
				}
				else if (!root)
				{
					// Allow PI to be the initial root; will be replaced if a START_ELEMENT follows.
					root = node;
				}

			case COMMENT:
				XmlNode* node = alloc::new(allocator, XmlNode);
				*node = { .kind = COMMENT, .value = event.value.copy(allocator), .doc = document };
				node.attributes.init(allocator);
				node.children.init(allocator);
				if (current)
				{
					current.children.push(node);
				}
				else if (!root)
				{
					// Allow top-level comments as fallback root nodes.
					root = node;
				}
		}
	}

	if (node_stack.len() > 0 || current) return XML_TAG_MISMATCH~;
	document.root = root;
	return document;
}

<* Loads and parses an XML document from a stream into a DOM tree using the temp allocator. *>
fn XmlDocument*? tload(InStream stream)
{
	return load(tmem, stream);
}

<* Parses an XML document from a string. *>
fn XmlDocument*? parse(Allocator allocator, String s)
{
	ByteReader reader;
	reader.init(s);
	return load(allocator, &reader);
}

<* Parses an XML document from a string using the temp allocator. *>
fn XmlDocument*? tparse(String s)
{
	return parse(tmem, s);
}


// ----------------------------------------------------------------------------
module std::encoding::xml::dom;
import std::encoding::xml::stream;
import std::collections, std::collections::map, std::collections::list, std::io;

/**
 * An XML node in the DOM tree.
 */
struct XmlNode
{
	XmlEventKind kind;
	String name;
	String value;
	HashMap{String, String} attributes;
	List{XmlNode*} children;
	XmlDocument* doc; // Back-pointer to owner document
}

/**
 * A parsed XML document.
 */
struct XmlDocument
{
	XmlNode* root;
	Allocator allocator;
}

alias NodeFilter = fn bool(XmlNode* node);

/**
 * Recursively searches for nodes matching the filter.
 */
fn void XmlNode.find_by_filter(&self, NodeFilter filter, List{XmlNode*}* results)
{
	if (filter(self)) results.push(self);
	foreach (child : self.children)
	{
		child.find_by_filter(filter, results);
	}
}

/**
 * Finds all nodes with the given name.
 */
fn void XmlNode.find_all(&self, String name, List{XmlNode*}* results)
{
	if (self.name == name) results.push(self);
	foreach (child : self.children)
	{
		child.find_all(name, results);
	}
}

/**
 * Finds the first node with the given name (depth-first).
 */
fn XmlNode* XmlNode.find(&self, String name)
{
	if (self.name == name) return self;
	foreach (child : self.children)
	{
		XmlNode* found = child.find(name);
		if (found) return found;
	}
	return null;
}

/**
 * Returns the text content of the node (from its first TEXT child).
 */
fn String? XmlNode.text(&self)
{
	foreach (child : self.children)
	{
		if (child.kind == TEXT) return child.value;
	}
	return io::EOF~;
}

/**
 * Sets the text content of the node, creating or updating a TEXT child.
 */
fn void XmlNode.set_text(&self, String text)
{
	foreach (child : self.children)
	{
		if (child.kind == TEXT)
		{
			child.set_value(text);
			return;
		}
	}
	// Create new text node
	XmlNode* node = alloc::new(self.doc.allocator, XmlNode);
	*node = { .kind = TEXT, .value = text.copy(self.doc.allocator), .doc = self.doc };
	node.attributes.init(self.doc.allocator);
	node.children.init(self.doc.allocator);
	self.children.push(node);
}

/**
 * Sets the node's name, handling memory management.
 */
fn void XmlNode.set_name(&self, String name)
{
	self.name.free(self.doc.allocator);
	self.name = name.copy(self.doc.allocator);
}

/**
 * Sets the node's value, handling memory management.
 */
fn void XmlNode.set_value(&self, String value)
{
	self.value.free(self.doc.allocator);
	self.value = value.copy(self.doc.allocator);
}

/**
 * Sets an attribute value.
 */
fn void XmlNode.set_attr(&self, String key, String value)
{
	if (self.attributes.has_key(key))
	{
		self.attributes.get(key)!!.free(self.doc.allocator);
	}
	self.attributes.set(key, value.copy(self.doc.allocator));
}

/**
 * Gets an attribute value.
 */
fn String? XmlNode.attr(&self, String key)
{
	return self.attributes.get(key);
}

/**
 * Frees the node and all its children.
 */
fn void XmlNode.free(&self, Allocator allocator)
{
	self.name.free(allocator);
	self.value.free(allocator);
	self.attributes.@each(; key, val)
	{
		val.free(allocator);
	};
	self.attributes.free();
	foreach (child : self.children)
	{
		child.free(allocator);
		alloc::free(allocator, child);
	}
	self.children.free();
}

/**
 * Recursively writes the node and its children to an XmlWriter.
 */
fn void? XmlNode.write(&self, XmlWriter* w)
{
	switch (self.kind)
	{
		case START_ELEMENT:
			w.open(self.name)!;
			self.attributes.@each(; key, val)
			{
				w.attr(key, val)!;
			};
			foreach (child : self.children)
			{
				child.write(w)!;
			}
			w.close_el(self.name)!;
		case TEXT:
			io::fprint(w, self.value)!;
		case PI:
			w.write("<?")!;
			w.write(self.name)!;
			w.write(" ")!;
			w.write(self.value)!;
			w.write("?>")!;
		case COMMENT:
			w.write("<!--")!;
			w.write(self.value)!;
			w.write("-->")!;
		default:
			break;
	}
}

/**
 * Writes the entire document to an XmlWriter.
 */
fn void? XmlDocument.write(&self, XmlWriter* w)
{
	if (self.root) self.root.write(w)!;
}

/**
 * Frees the document tree and the document container itself.
 */
fn void XmlDocument.free(XmlDocument* self)
{
	if (!self) return;
	Allocator allocator = self.allocator;
	if (self.root)
	{
		self.root.free(allocator);
		alloc::free(allocator, self.root);
	}
	alloc::free(allocator, self);
}

// ----------------------------------------------------------------------------
module std::encoding::xml::stream;
import std::encoding::xml::internal @public;
import std::io;

struct XmlReader
{
	InStream stream;
	Parser parser;
	DString buffer;
	DString tag_stack;
	Allocator allocator;
	Ret peeked_res;
}

fn void? XmlReader.init(&self, InStream stream, void* stack, usz stacksize, Allocator allocator = tmem)
{
	mem::clear(self, XmlReader::size);
	self.stream = stream;
	self.allocator = allocator;
	internal::init(&self.parser, stack, stacksize);
	self.buffer.init(allocator, 256);
	self.tag_stack.init(allocator, 256);
}

fn void XmlReader.destroy(&self)
{
	self.buffer.free();
	self.tag_stack.free();
}

fn Ret? XmlReader.low_level_next(&self)
{
	if (self.peeked_res != Ret.OK)
	{
		Ret res = self.peeked_res;
		self.peeked_res = Ret.OK;
		return res;
	}
	while (true)
	{
		char? c_opt = self.stream.read_byte();
		if (catch err = c_opt)
		{
			return err~;
		}
		Ret res = internal::xml_parse_internal(&self.parser, (int)c_opt);
		if (res < OK)
		{
			switch (res)
			{
				case EEOF:   return io::UNEXPECTED_EOF~;
				case EREF:   return xml::XML_INVALID_REF~;
				case ECLOSE: return xml::XML_TAG_MISMATCH~;
				case ESTACK: return xml::XML_STACK_OVERFLOW~;
				case ESYN:   return xml::XML_SYNTAX~;
				default: unreachable();
			}
		}
		if (res > OK) return res;
	}
}

fn void? XmlReader.close(&self)
{
	if (internal::eof(&self.parser) != OK) return xml::XML_SYNTAX~;
	return;
}

fn XmlEvent? XmlReader.next_event(&self)
{
	while (true)
	{
		Ret? res_opt = self.low_level_next();
		if (catch err = res_opt)
		{
			if (err == io::EOF)
			{
				if (internal::eof(&self.parser) != Ret.OK) return xml::XML_SYNTAX~;
				return io::EOF~;
			}
			return err~;
		}
		Ret res = res_opt;
		switch (res)
		{
			case ELEMSTART:
			{
				String name = self.parser.elem_view();
				self.tag_stack.append(name);
				self.tag_stack.append('\0');
				return { .kind = START_ELEMENT, .name = name };
			}
			case ELEMEND:
			{
				String tags = self.tag_stack.str_view();
				if (tags.len == 0) return xml::XML_TAG_MISMATCH~;
				// The last tag is before the last null byte.
				// Find the second-to-last null byte (or start of string).
				sz last_null = tags.len - 1;
				sz prev_null = last_null;
				while (prev_null > 0 && tags[prev_null - 1] != 0) prev_null--;

				String name = tags[prev_null : last_null - prev_null];
				self.tag_stack.chop(prev_null);
				return { .kind = END_ELEMENT, .name = name };
			}
			case ATTRSTART:
				String name = self.parser.attr_view();
				self.buffer.clear();
				while (true)
				{
					Ret next_res = self.low_level_next()!;
					if (next_res == ATTRVAL)
					{
						self.buffer.append(self.parser.data_view());
					}
					else if (next_res == ATTREND) break;
				}
				return { .kind = ATTRIBUTE, .name = name, .value = self.buffer.str_view() };
			case CONTENT:
				self.buffer.clear();
				self.buffer.append(self.parser.data_view());
				while (true)
				{
					Ret? next_res_opt = self.low_level_next();
					if (catch err = next_res_opt)
					{
						if (err == io::EOF) break;
						return err~;
					}
					Ret next_res = next_res_opt;
					if (next_res == Ret.CONTENT)
					{
						self.buffer.append(self.parser.data_view());
					}
					else
					{
						self.peeked_res = next_res;
						break;
					}
				}
				return { .kind = TEXT, .value = self.buffer.str_view() };
			case PISTART:
				String name = self.parser.pi_view();
				self.buffer.clear();
				while (true)
				{
					Ret next_res = self.low_level_next()!;
					if (next_res == PICONTENT)
					{
						self.buffer.append(self.parser.data_view());
					}
					else if (next_res == PIEND) break;
				}
				return { .kind = PI, .name = name, .value = self.buffer.str_view() };
			default:
				continue;
		}
	}
}

struct XmlWriter (OutStream)
{
	OutStream stream;
	bool in_tag;
}

fn void XmlWriter.init(&self, OutStream stream)
{
	*self = { .stream = stream };
}

fn void? XmlWriter.start_doc(&self, String version = "1.0", String encoding = "UTF-8")
{
	self.stream.write("<?xml version=\"")!;
	self.stream.write(version)!;
	self.stream.write("\" encoding=\"")!;
	self.stream.write(encoding)!;
	self.stream.write("\"?>\n")!;
}

fn void? XmlWriter.end_doc(&self)
{
	if (self.in_tag)
	{
		self.stream.write(">")!;
		self.in_tag = false;
	}
}

fn void? XmlWriter.open(&self, String name)
{
	if (self.in_tag) self.stream.write(">")!;
	self.stream.write("<")!;
	self.stream.write(name)!;
	self.in_tag = true;
}

fn void? XmlWriter.close_el(&self, String name, bool self_closing = false)
{
	if (self.in_tag)
	{
		if (self_closing)
		{
			self.stream.write(" />")!;
		}
		else
		{
			self.stream.write(">")!;
			self.stream.write("</")!;
			self.stream.write(name)!;
			self.stream.write(">")!;
		}
		self.in_tag = false;
	}
	else
	{
		self.stream.write("</")!;
		self.stream.write(name)!;
		self.stream.write(">")!;
	}
}

fn void? XmlWriter.empty(&self, String name)
{
	self.open(name)!;
	self.close_el(name, true)!;
}

fn void? XmlWriter.attr(&self, String name, String value)
{
	assert(self.in_tag);
	self.stream.write(" ")!;
	self.stream.write(name)!;
	self.stream.write("=\"")!;
	self.write_escaped(value)!;
	self.stream.write("\"")!;
}

fn void? XmlWriter.write_escaped(&self, String s)
{
	foreach (c : s)
	{
		switch (c)
		{
			case '<': self.stream.write("&lt;")!;
			case '>': self.stream.write("&gt;")!;
			case '&': self.stream.write("&amp;")!;
			case '"': self.stream.write("&quot;")!;
			case '\'': self.stream.write("&apos;")!;
			default: self.stream.write_byte(c)!;
		}
	}
}

fn sz? XmlWriter.write(&self, char[] bytes) @dynamic
{
	if (self.in_tag)
	{
		self.stream.write(">")!;
		self.in_tag = false;
	}
	self.write_escaped((String)bytes)!;
	return bytes.len;
}

fn void? XmlWriter.write_byte(&self, char c) @dynamic
{
	char[1] b = { c };
	self.write(b[..])!;
}

fn void? XmlWriter.close(&self) @dynamic
{
	if (self.in_tag)
	{
		self.stream.write(">")!;
		self.in_tag = false;
	}
	return self.stream.close();
}


module std::encoding::xml::internal @private;
$exec("parser.c3", { "state", "yxml.c3.in" });
