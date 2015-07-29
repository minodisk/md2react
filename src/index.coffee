mdast = require 'mdast'
preprocess = require './preprocess'

ATTR_WHITELIST = ['href', 'src', 'target']

$ = React.createElement

defaultHTMLWrapperComponent = React.createClass
  _update: ->
    current = @props.html
    if @_lastHtml isnt current
      @_lastHtml = current
      node = @refs.htmlWrapper.getDOMNode()
      node.contentDocument.body.innerHTML = @props.html
      node.style.height = node.contentWindow.document.body.scrollHeight + 'px'
      node.style.width  = node.contentWindow.document.body.scrollWidth  + 'px'

  componentDidUpdate: -> @_update()
  componentDidMount: -> @_update()

  render: ->
    $ 'iframe',
      ref: 'htmlWrapper'
      html: @props.html
      style:
        border: 'none'

isValidDocument = (doc) ->
  parsererrorNS = (new DOMParser()).parseFromString('INVALID', 'text/xml').getElementsByTagName("parsererror")[0].namespaceURI
  doc.getElementsByTagNameNS(parsererrorNS, 'parsererror').length == 0

getPropsFromHTMLNode = (node, attrWhitelist) ->
  string =
    if node.subtype is 'folded'
      node.startTag.value + node.endTag.value
    else if node.subtype is 'void'
      node.value
    else
      null
  if !string?
    return null

  parser = new DOMParser()
  doc = parser.parseFromString(string, 'text/html')
  if !isValidDocument(doc)
    return null

  attrs = doc.body.firstElementChild.attributes
  props = {}
  for i in [0...attrs.length]
    attr = attrs.item(i)
    if !attrWhitelist? or (attr.name in attrWhitelist)
      props[attr.name] = attr.value
  props

module.exports = class Compiler

  constructor: (@options = {}) ->
    @sanitize = @options.sanitize ? true
    @htmlWrapperComponent = @options.htmlWrapperComponent ? defaultHTMLWrapperComponent
    @rawValueWrapper = @options.rawValueWrapper ? (text) -> text
    @highlight = @options.highlight ? (code, lang, key) ->
      $ 'pre', {key, className: 'code'}, [
        $ 'code', {key: key+'-_inner-code'}, code
      ]

  compile: (raw) ->
    ast = mdast.parse raw, @options
    [ast, defs] = preprocess(ast, raw, @options)
    ast = @options.preprocessAST?(ast) ? ast
    @_compile(ast, defs)

  _compile: (node, defs, parentKey='_start', tableAlign = null) ->
    key = parentKey+'_'+node.type
    fn = @[node.type]
    if !fn?
      throw node.type + ' is unsuppoted node type. report to https://github.com/mizchi/md2react/issues'
    fn.call(@, node, defs, key, tableAlign)

  toChildren: (node, defs, parentKey, tableAlign = []) ->
    return (for child, i in node.children
      @_compile(child, defs, parentKey+'_'+i, tableAlign))

  # No child
  text: (node, defs, key, tableAlign) -> @rawValueWrapper node.value
  escape: (node, defs, key, tableAlign) -> '\\'
  break: (node, defs, key, tableAlign) -> $ 'br', {key}
  horizontalRule: (node, defs, key, tableAlign) -> $ 'hr', {key}
  image: (node, defs, key, tableAlign) -> $ 'img', {key, src: node.src, title: node.title, alt: node.alt}
  inlineCode: (node, defs, key, tableAlign) -> $ 'code', {key, className:'inlineCode'}, node.value
  code: (node, defs, key, tableAlign) -> @highlight node.value, node.lang, key

  # Has children
  root: (node, defs, key, tableAlign) -> $ 'div', {key}, @toChildren(node, defs, key)
  strong: (node, defs, key, tableAlign) -> $ 'strong', {key}, @toChildren(node, defs, key)
  emphasis: (node, defs, key, tableAlign) -> $ 'em', {key}, @toChildren(node, defs, key)
  delete: (node, defs, key, tableAlign) -> $ 's', {key}, @toChildren(node, defs, key)
  paragraph: (node, defs, key, tableAlign) -> $ 'p', {key}, @toChildren(node, defs, key)
  link: (node, defs, key, tableAlign) -> $ 'a', {key, href: node.href, title: node.title}, @toChildren(node, defs, key)
  heading: (node, defs, key, tableAlign) -> $ ('h'+node.depth.toString()), {key}, @toChildren(node, defs, key)
  list: (node, defs, key, tableAlign) -> $ (if node.ordered then 'ol' else 'ul'), {key}, @toChildren(node, defs, key)
  listItem: (node, defs, key, tableAlign) ->
    className =
      if node.checked is true
        'checked'
      else if node.checked is false
        'unchecked'
      else
        ''
    $ 'li', {key, className}, @toChildren(node, defs, key)
  blockquote: (node, defs, key, tableAlign) -> $ 'blockquote', {key}, @toChildren(node, defs, key)

  linkReference: (node, defs, key, tableAlign) ->
    for def in defs
      if def.type is 'definition' and def.identifier is node.identifier
        return $ 'a', {key, href: def.link, title: def.title}, @toChildren(node, defs, key)
    # There's no corresponding definition; render reference as plain text.
    if node.referenceType is 'full'
      $ 'span', {key}, [
        '['
        @toChildren(node, defs, key)
        ']'
        "[#{node.identifier}]"
      ]
    else # referenceType must be 'shortcut'
      $ 'span', {key}, [
        '['
        @toChildren(node, defs, key)
        ']'
      ]

  # Footnote
  footnoteReference: (node, defs, key, tableAlign) ->
    title = ''
    for def in defs
      if def.footnoteNumber is node.footnoteNumber
        title = def.link ? "..." # FIXME: use def.children (stringification needed)
        return $ 'sup', {key, id: "fnref#{node.footnoteNumber}"}, [
          $ 'a', {key: key+'-a', href: "#fn#{node.footnoteNumber}", title}, "#{node.footnoteNumber}"
        ]
    # There's no corresponding definition; render reference as plain text.
    $ 'span', {key}, "[^#{node.identifier}]"
  footnoteDefinitionCollection: (node, defs, key, tableAlign) ->
    items = node.children.map (def, i) ->
      k = key+'-ol-li'+i
      # If `def` has children, we use them as `defBody`. And If `def` doesn't
      # have any, then it should have `link` text, so we use it.
      defBody = null
      if def.children?
        # If `def`s last child is a paragraph, append an anchor to `defBody`.
        # Otherwise we append nothing like Qiita does.
        # FIXME: We should not mutate a given AST.
        if (para = def.children[def.children.length - 1]).type is 'paragraph'
          para.children.push
            type: 'text'
            value: ' '
          para.children.push
            type: 'link'
            href: "#fnref#{def.footnoteNumber}"
            children: [{type: 'text', value: '↩'}]
        defBody = @toChildren(def, defs, key)
      else
        defBody = $ 'p', {key: k+'-p'}, [
          def.link
          ' '
          $ 'a', {key: k+'-p-a', href: "#fnref#{def.footnoteNumber}"}, '↩'
        ]
      $ 'li', {key: k, id: "fn#{def.footnoteNumber}"}, defBody
    $ 'div', {key, className: 'footnotes'}, [
      $ 'hr', {key: key+'-hr'}
      $ 'ol', {key: key+'-ol'}, items
    ]

  # Table
  table: (node, defs, key, tableAlign) -> $ 'table', {key}, @toChildren(node, defs, key, node.align)
  tableHeader: (node, defs, key, tableAlign) ->
    $ 'thead', {key}, [
      $ 'tr', {key: key+'-_inner-tr'}, node.children.map (cell, i) =>
        k = key+'-th'+i
        $ 'th', {key: k, style: {textAlign: tableAlign[i] ? 'left'}}, @toChildren(cell, defs, k)
    ]

  tableRow: (node, defs, key, tableAlign) ->
    # $ 'tr', {key}  , [$ 'td', {key: key+'_inner-td'}, @toChildren(node, defs, key)]
    $ 'tbody', {key}, [
      $ 'tr', {key: key+'-_inner-td'}, node.children.map (cell, i) =>
        k = key+'-td'+i
        $ 'td', {key: k, style: {textAlign: tableAlign[i] ? 'left'}}, @toChildren(cell, defs, k)
    ]
  tableCell: (node, defs, key, tableAlign) -> $ 'span', {key}, @toChildren(node, defs, key)

  # Raw html
  html: (node, defs, key, tableAlign) ->
    if node.subtype is 'raw'
      $ @htmlWrapperComponent, key: key, html: node.value
    else if node.subtype is 'computed'
      k = key+'_'+node.tagName
      props = {}
      for name, value of node.attrs ? {}
        props[name] = value
      props.key = k
      if node.children?
        $ node.tagName, props, @toChildren(node, defs, k)
      else
        $ node.tagName, props
    else if node.subtype is 'folded'
      k = key+'_'+node.tagName
      props = getPropsFromHTMLNode(node, ATTR_WHITELIST) ? {}
      props.key = k
      $ node.startTag.tagName, props, @toChildren(node, defs, k)
    else if node.subtype is 'void'
      k = key+'_'+node.tagName
      props = getPropsFromHTMLNode(node, ATTR_WHITELIST) ? {}
      props.key = k
      $ node.tagName, props
    else if node.subtype is 'special'
      $ 'span', {
        key: key + ':special'
        style: {
          color: 'gray'
        }
      }, node.value
    else
      $ 'span', {
        key: key + ':parse-error'
        style: {
          backgroundColor: 'red'
          color: 'white'
        }
      }, node.value
