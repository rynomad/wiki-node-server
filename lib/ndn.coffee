ndn   = require("ndn-lib")
utils = require("ndn-utils")
ndnio = require('ndn-io')

rOpts =
  silent: true,
  execArgv: ["wiki"]

ndnr  = require("level-ndn")

keys  = require('./key')

initBuffer = []
ioUp = false



wikiNDNInit = (pagehandler, sitemap) ->

  ac = () ->
    console.log "io init from ndn.coffee"


  ioInit = (cert, pri, pub) ->
    ndnio.useNDN(ndn)
    ndnio.importPKI cert, pri, pub
    ndnio.initFace('tcp', {host: "localhost", port: 6464}, ac)

  if ioUp == false

    ioUp = true
    keys ioInit

RegisteredPrefix = (prefix, closure) ->
  this.prefix = prefix
  this.closure = closure
  this

asSlug = (name) ->
  name.replace(/\s/g, '-').replace(/[^A-Za-z0-9-]/g, '').toLowerCase()

face = new ndn.Face({host:"localhost", port: 6464})
localid = null
host = null

neighbors = []
neighborhood = {}
registeredPages = {}
pageBuffer = {}

registerPageInterestHandler = (pagehandler) ->

  pageInterestHandler = (prefix, interest, transport) ->
    console.log("got interest in pageInterestHandler")
    slug = interest.name.components[2].toEscapedString()
    int = utils.getSegmentInteger(interest.name)
    if (!pageBuffer[slug])
      console.log("pagehandler.get ", slug)
      pagehandler.get slug, (e, page, status) ->
        pageBuffer[slug] = utils.chunkArbitraryData({type: "object", thing: page, freshness: 60 * 60 * 1000, version: page.journal[page.journal.length - 1].date, uri: "wiki/page/"+ slug}).array
        toSend = pageBuffer[slug][int]
        transport.send(toSend.buffer)
    else
      transport.send(pageBuffer[slug][int].buffer)

  uri = "/wiki/page"
  closure = new ndn.Face.CallbackClosure null, null, pageInterestHandler, new ndn.Name(uri), face.transport
  registeredPrefix = new RegisteredPrefix(new ndn.Name(uri), closure)
  ndn.Face.registeredPrefixTable.push registeredPrefix
  #console.log("registered",uri," preifx", ndn.Face.registeredPrefixTable)

registerSelf = (pagehandler, hostOrSlug) ->
  console.log("registering own face'")
  name = new ndn.Name("localhost/nfd/fib/add-nexthop")
  console.log host
  param =
    uri: "wiki/"

  param.uri += hostOrSlug || host
  console.log("nexthop uri:", param.uri)
  registeredPages[hostOrSlug] = true
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
    if ((data.content.toString() == "success") &&(!hostOrSlug))
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

  if ((host != thishost) && (thishost != "localhost") && (thishost != "127.0.0.1") && (thishost != "66.185.108.210"))
    params =
      host: thishost,
      port: 6464,
      protocol: "tcp"
      nextHop:
        uri: "wiki/" + thishost

    #console.log thishost, host

    dat = new ndn.Data(new ndn.Name(''), new ndn.SignedInfo(), JSON.stringify(params))
    dat.signedInfo.setFields()
    dat.sign()
    enc = dat.wireEncode()

    com = new ndn.Name("localhost/nfd/faces/create")

    com.append(enc.buffer)
    inst = new ndn.Interest(com)


    ond = (interest, data) ->
      neighborhood[site].sitemap = JSON.parse(data.content.toString())

      #console.log("got remote sitemap,", neighborhood[site].sitemap)
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
      #console.log(neighborhood[site], thishost)
      uri = "/wiki/"+ thishost + "/sitemap"
      hashname = new ndn.Name(uri)
      inter = new ndn.Interest(hashname)
      face.expressInterest(inter, ond, ont)



    onTimeout = (interest) ->
      console.log("makeFace timeout", site)

    face.expressInterest(inst, onData, onTimeout)

registerNeighbor = (site) ->

  neighbors.push site
  neighborhood[site] =
    registered: true

  makeFace(site)

publishAction = (action, page) ->
  #console.log "action.page = ", action.page
  journalnum = action.page.journal.length - 1
  action.page = undefined
  publishOptions =
    uri: "wiki/page/" + action.slug + "/" + journalnum ,
    freshness: 60 * 60 * 1000 ,
    type: 'object',
    thing: action

  if ioUp == true
    ndnio.publishObject publishOptions
  else
    initBuffer.push publishOptions


importTriggered = false

importPages = (pagehandler, sitemap) ->
  if importTriggered == false
    importTriggered = true
    publisher = (pageIndex) ->
      pagehandler.get sitemap[pageIndex].slug, (e, page, status) ->
        pagePublisher = (i) ->
          publishOptions =
            uri: "wiki/page/" + asSlug(page.title) + "/" + i ,
            version: false ,
            freshness: 60 * 60 * 1000 ,
            type: 'object',
            thing: page.journal[i]

          ndnio.publishObject publishOptions, () ->
            console.log "progress report: ", pageIndex, i
            i++
            if (i < page.journal.length)
              pagePublisher(i)
            else if pageIndex < sitemap.length - 1
              pageIndex++
              publisher(pageIndex)
        pagePublisher(0)

     publisher(0)



module.exports = (pagehandler, action, argv) ->
  oldnum = neighbors.length
  scan = (page) ->
    for item in page.story
      if (item.site? && !neighborhood[item.site])
        registerNeighbor(item.site)

    for action in page.journal
      if (action.site? && !neighborhood[action.site])
        registerNeighbor(action.site)



  if (action?)
    publishAction action
    console.log(action)

    sites = []
    sites.push(action.site) if action.site?
    sites.push(action.item.site) if (action.item? && action.item.site?)
    sites.push(action.fork) if action.fork?
    for site in sites
      registerNeighbor(site) if (!neighborhood[site])

  else if argv?
    console.log("got argv")




  if pagehandler?
    pagehandler.pages (e, sitemap) ->
      ndnr.tangle("wiki", null, null, ()->

            console.log "repo tangled"
            ndnr.init("wiki", ()->
                       console.log("open")
                     , () ->


                       wikiNDNInit pagehandler, sitemap
                     )
           )

      for page in sitemap
        registerSelf(pagehandler, "page/" + page.slug)
        pagehandler.get page.slug, (e, page, status) ->
          console.log("got page from pagehandler",page.title)
          scan page

    registerSelf(pagehandler)
    #registerPageInterestHandler(pagehandler)

