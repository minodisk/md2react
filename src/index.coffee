mdast = require 'mdast'
uuid = require 'uuid'
preprocess = require './preprocess'

ATTR_WHITELIST = ['href', 'src', 'target']

$ = React.createElement

toChildren = (node, parentKey, tableAlign = []) ->
  return (for child, i in node.children
    compile(child, parentKey+'_'+i, tableAlign))

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

# Override by option
sanitize = null
highlight = null
compile = (node, parentKey='_start', tableAlign = null) ->
  key = parentKey+'_'+node.type

  switch node.type
    # No child
    when 'text'           then rawValueWrapper node.value
    when 'escape'         then '\\'
    when 'break'          then $ 'br', {key}
    when 'horizontalRule' then $ 'hr', {key}
    when 'image'          then $ 'img', {key, src: node.src, title: node.title, alt: node.alt}
    when 'inlineCode'     then $ 'code', {key, className:'inlineCode'}, node.value
    when 'code'           then highlight node.value, node.lang, key

    # Has children
    when 'root'       then $ 'div', {key}, toChildren(node, key)
    when 'strong'     then $ 'strong', {key}, toChildren(node, key)
    when 'emphasis'   then $ 'em', {key}, toChildren(node, key)
    when 'delete'     then $ 's', {key}, toChildren(node, key)
    when 'paragraph'  then $ 'p', {key}, toChildren(node, key)
    when 'link'       then $ 'a', {key, href: node.href, title: node.title}, toChildren(node, key)
    when 'heading'    then $ ('h'+node.depth.toString()), {key}, toChildren(node, key)
    when 'list'       then $ (if node.ordered then 'ol' else 'ul'), {key}, toChildren(node, key)
    when 'listItem'
      className =
        if node.checked is true
          'checked'
        else if node.checked is false
          'unchecked'
        else
          ''
      $ 'li', {key, className}, toChildren(node, key)
    when 'blockquote' then $ 'blockquote', {key}, toChildren(node, key)

    # Table
    when 'table'       then $ 'table', {key}, toChildren(node, key, node.align)
    when 'tableHeader'
      $ 'thead', {key}, [
        $ 'tr', {key: key+'-_inner-tr'}, node.children.map (cell, i) ->
          k = key+'-th'+i
          $ 'th', {key: k, style: {textAlign: tableAlign[i] ? 'left'}}, toChildren(cell, k)
      ]

    when 'tableRow'
      # $ 'tr', {key}  , [$ 'td', {key: key+'_inner-td'}, toChildren(node, key)]
      $ 'tbody', {key}, [
        $ 'tr', {key: key+'-_inner-td'}, node.children.map (cell, i) ->
          k = key+'-td'+i
          $ 'td', {key: k, style: {textAlign: tableAlign[i] ? 'left'}}, toChildren(cell, k)
      ]
    when 'tableCell'   then $ 'span', {key}, toChildren(node, key)

    # Raw html
    when 'html'
      if node.subtype is 'folded'
        k = key+'_'+node.tagName
        props = getPropsFromHTMLNode(node, ATTR_WHITELIST) ? {}
        props.key = k
        $ node.startTag.tagName, props, toChildren(node, k)
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
    else
      throw node.type + ' is unsuppoted node type. report to https://github.com/mizchi/md2react/issues'

htmlWrapperComponent = null
rawValueWrapper = null

module.exports = (raw, options = {}) ->
  sanitize = options.sanitize ? true
  rawValueWrapper = options.rawValueWrapper ? (text) -> text

  highlight = options.highlight ? (code, lang, key) ->
    $ 'pre', {key, className: 'code'}, [
      $ 'code', {key: key+'-_inner-code'}, code
    ]
  ast = mdast.parse raw, options
  ast = preprocess(ast)
  ast = options.preprocessAST?(ast) ? ast
  compile(ast)
