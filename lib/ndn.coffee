ndn = require("ndn-lib")

face = new ndn.Face({host:"localhost", port: 6464})



neighbors = []
neighborhood = {}
makeFace = (site) ->
  console.log("making face", site)
  params =
    host: site.split(':')[0],
    port: 6464,
    protocol: "tcp"
    nextHop:
      uri: "wiki"

  console.log params

  dat = new ndn.Data(new ndn.Name(''), new ndn.SignedInfo(), JSON.stringify(params))
  dat.signedInfo.setFields()
  dat.sign()
  enc = dat.wireEncode()

  com = new ndn.Name("localhost/nfd/faces/create")

  com.append(enc.buffer)
  inst = new ndn.Interest(com)
  face.expressInterest(inst)

registerNeighbor = (site) ->

  neighbors.push site
  neighborhood[site] = true
  makeFace(site)


module.exports = (pagehandler, action) ->
  oldnum = neighbors.length
  scan = (page) ->
    for item in page.story
      if (item.site? && !neighborhood[item.site])
        registerNeighbor(item.site)

    for action in page.journal
      if (action.site? && !neighborhood[action.site])
        registerNeighbor(action.site)

  if action?
    sites = []
    sites.push(action.site) if action.site?
    sites.push(action.item.site) if (action.item? && action.item.site?)
    sites.push(action.fork) if action.fork?
    for site in sites
      registerNeighbor(site) if (!neighborhood[site])
  else
    pagehandler.pages (e, sitemap) ->
      for page in sitemap
        pagehandler.get page.slug, (e, page, status) ->
          scan page
