# convert a human-readable size (usually used by xfs_quota) to kb unit which is
# the unit reported by xfs_quota when not used -h flag
module.exports =
  size_table:
    "M": 1024
    "G": 1024 * 1024

  unit_table:
    "M": 1
    "G": 1024

  unit: (size) ->
    memoryUnit = size?.match(/\d+([A-Z])/)?[1]
    if !memoryUnit then '' else memoryUnit

  convert: (size) ->
    return 0 if size == "0"
    parseFloat(size) * @size_table[@unit(size)]

  convertUnit: (size, unit) ->
    ratio = @unit_table[@unit(size)] / @unit_table[unit]
    parseInt((parseFloat(size) * ratio), 10) + unit
