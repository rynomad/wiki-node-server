
levelup = require('levelup')
path = process.env.HOME || process.env.USERPROFILE || process.env.HOMEPATH
module.exports = (callback) ->
  levelup path + "/.wiki/keys"
  , (err, db) ->

    # console.log(err, db)
    db.get "public", (err, value) ->
      if err
        if err.notFound
          pki = require("node-forge").pki
          pki.rsa.generateKeyPair
            bits: 2048
          , (er, keys) ->
            cert = pki.createCertificate()
            cert.publicKey = keys.publicKey
            cert.serialNumber = "01"
            cert.validity.notBefore = new Date()
            cert.validity.notAfter = new Date()
            cert.validity.notAfter.setFullYear cert.validity.notBefore.getFullYear() + 1
            cert.sign keys.privateKey
            pem = pki.certificateToPem(cert)
            pubPem = pki.publicKeyToPem(keys.publicKey)
            priOpenPem = pki.privateKeyToPem(keys.privateKey)

            ops = [
              {
                type: "put"
                key: "public"
                value: pubPem
              }
              {
                type: "put"
                key: "private"
                value: priOpenPem
              }
              {
                type: "put"
                key: "certificate"
                value: pem
              }
            ]
            db.batch ops, (err) ->
              console.log "batch finished"
              callback(pem, priOpenPem, pubPem)  unless err
              return

            return

        else

          # I/O or other error, pass it up the callback chain
          console.log "IO err", err
          callback err
      else
        pub = value
        db.get "private", (err, value) ->
          pri = value
          db.get "certificate", (err, value) ->
            cert = value
            callback(cert, pri, pub)
            return

          return

      return

    return
