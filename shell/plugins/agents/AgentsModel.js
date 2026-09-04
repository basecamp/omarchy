function numberValue(value) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : 0
}

function totalTokens(provider) {
  var total = 0
  var models = provider.modelUsage || {}
  for (var id in models) {
    var usage = models[id] || {}
    total += numberValue(usage.inputTokens)
      + numberValue(usage.outputTokens)
      + numberValue(usage.cacheReadInputTokens)
      + numberValue(usage.cacheCreationInputTokens)
  }
  return total
}

function sortByUsage(providers) {
  return providers.sort(function(a, b) {
    return totalTokens(b) - totalTokens(a)
      || numberValue(b.totalPrompts) - numberValue(a.totalPrompts)
      || String(a.providerName || a.providerId).localeCompare(String(b.providerName || b.providerId))
      || String(a.providerId).localeCompare(String(b.providerId))
  })
}

if (typeof module !== "undefined") module.exports = { sortByUsage, totalTokens }
