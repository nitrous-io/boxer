process.env.NODE_ENV = 'test'

global.context = global.describe
global.xcontext = global.xdescribe
global.specify = global.it
global.xspecify = global.xit
global.its = global.it
global.xits = global.xit

global.sinon = require 'sinon'
global.assert = require 'should'
global.expect = require 'expect.js'
global.expect = require('sinon-expect').enhance(expect, sinon, 'was')

global.cleanDB = require './support/clean_db'

#global.Factory = require './factories'

