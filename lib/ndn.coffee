ndn = require("ndn-lib")
utils = require("ndn-utils")



face = new ndn.Face({host:"localhost", port: 6464})
localid = null
host = null

neighbors = []
neighborhood = {}


registerSelf = (pagehandler, hostOrSlug) ->
  console.log("registering own face'", pagehandler)
  name = new ndn.Name("localhost/nfd/fib/add-nexthop")
  console.log host
  param =
    uri: "wiki/"

  param.uri += hostOrSlug || host
  console.log(param.uri)

  d = new ndn.Data(new ndn.Name(''), new ndn.SignedInfo(), JSON.stringify(param))
  d.signedInfo.setFields()
  d.sign()
  enc = d.wireEncode()
  name.append(enc.buffer)
  inst = new ndn.Interest(name)

  onInterest = (prefix, interest, transport) ->
    if (interest.name.components[2].toEscapedString() == "sitemap")
      pagehandler.pages (e, sitemap) ->
        d = new ndn.Data(interest.name, new ndn.SignedInfo(), JSON.stringify(sitemap))
        d.signedInfo.setFields()
        d.sign()
        enc = d.wireEncode()
        transport.send(enc.buffer)

  onData = ( interest, data, something) ->
    if (data.content.toString() == "success")
      registeredPrefix =
        prefix : new ndn.Name(param.uri)
        closure : new ndn.Face.CallbackClosure(null, null, onInterest, param.uri, face.transport)

      ndn.Face.registeredPrefixTable.push(registeredPrefix)


  onTimeout = (name, interest, something) ->
    console.log('timeout for add nexthop', name, interest, something)

  face.expressInterest(inst, onData, onTimeout)




makeFace = (site) ->
  console.log("making face", site)
  thishost = site.split(':')[0]
  params =
    host: thishost,
    port: 6464,
    protocol: "tcp"
    nextHop:
      uri: "wiki/" + thishost

  console.log params.nextHop

  dat = new ndn.Data(new ndn.Name(''), new ndn.SignedInfo(), JSON.stringify(params))
  dat.signedInfo.setFields()
  dat.sign()
  enc = dat.wireEncode()

  com = new ndn.Name("localhost/nfd/faces/create")

  com.append(enc.buffer)
  inst = new ndn.Interest(com)


  ond = (interest, data) ->
    neighborhood[site].sitemap = JSON.parse(data.content.toString())

    console.log("got remote sitemap,", neighborhood[site].sitemap)
    for page in neighborhood[site].sitemap
      nexthop =
        uri: "wiki/page/" + page.slug,
        faceID : neighborhood[site].faceID,

      d = new ndn.Data(new ndn.Name(), new ndn.SignedInfo(), JSON.stringify(nexthop))
      d.signedInfo.setFields()
      d.sign()
      n = new ndn.Name("localhost/nfd/fib/add-nexthop")
      n.append(d.wireEncode().buffer)
      i = new ndn.Interest(n)
      face.expressInterest(i)

  ont = (timeout, intrerest) ->
    console.log("getremoteKeyTimeout")

  onData = (interest, data) ->
    console.log("makeFace got Response", data.content.toString())
    neighborhood[site].faceID = JSON.parse(data.content.toString()).faceID
    #neighborhood[site].hashName = JSON.parse(data.content).ndndid
    console.log(neighborhood[site], thishost)
    uri = "/wiki/"+ thishost + "/sitemap"
    hashname = new ndn.Name(uri)
    console.log(hashname)
    inter = new ndn.Interest(hashname)
    console.log(inter)
    face.expressInterest(inter, ond, ont)



  onTimeout = (interest) ->
    console.log("makeFace timeout", site)

  face.expressInterest(inst, onData, onTimeout)

registerNeighbor = (site) ->

  neighbors.push site
  neighborhood[site] =
    registered: true

  makeFace(site)


module.exports = (pagehandler, action, argv) ->
  oldnum = neighbors.length
  scan = (page) ->
    for item in page.story
      if (item.site? && !neighborhood[item.site])
        registerNeighbor(item.site)

    for action in page.journal
      if (action.site? && !neighborhood[action.site])
        registerNeighbor(action.site)

  if action?
    console.log(action)
    sites = []
    sites.push(action.site) if action.site?
    sites.push(action.item.site) if (action.item? && action.item.site?)
    sites.push(action.fork) if action.fork?
    for site in sites
      registerNeighbor(site) if (!neighborhood[site])
  else if argv?
    console.log("got argv")
    parts = argv.url.split("//")[1]
    console.log parts
    host = parts.split(":")[0]
    console.log(host)




  if pagehandler?
    pagehandler.pages (e, sitemap) ->
      for page in sitemap
        registerSelf(pagehandler, "page/" + page.slug)
        pagehandler.get page.slug, (e, page, status) ->
          scan page

    registerSelf(pagehandler)
