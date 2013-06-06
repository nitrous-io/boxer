ConvertSize = require '../../app/lib/convert_size'

describe 'Convert Size', ->
  it 'extracts unit metrics of the size', ->
    expect(ConvertSize.unit("0")).to.eql ""
    expect(ConvertSize.unit("155.9M")).to.eql "M"
    expect(ConvertSize.unit("1G")).to.eql "G"

  it 'convert human-readable size to kb', ->
    expect(ConvertSize.convert("0")).to.eql 0
    expect(ConvertSize.convert("155.9M")).to.eql 159641.6
    expect(ConvertSize.convert("1G")).to.eql 1048576

  it 'converts size from one unit to another', ->
    expect(ConvertSize.convertUnit("1.5G", "M")).to.eql "1536M"
    expect(ConvertSize.convertUnit("15M", "M")).to.eql "15M"
    expect(ConvertSize.convertUnit("2048M", "G")).to.eql "2G"
    expect(ConvertSize.convertUnit("0.2G", "M")).to.eql "204M"
