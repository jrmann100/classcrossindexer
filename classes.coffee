fs = require 'fs'
http = require 'http'
url = require 'url'

allClasses = JSON.parse fs.readFileSync "classes.json"

console.log "Resolving double entries"
tempList = []
markForDeletion = []
for person in allClasses
  if person.name in tempList
    markForDeletion.push person
    console.log "DoubleEntryFind: #{person} has multiple entries"
  else
    tempList.push person.name
console.log "DoubleEntryFind: #{markForDeletion} marked for deletion"
for m in markForDeletion
  allClasses.pop m
console.log "DoubleEntryFind: deleted double entries"


findPerson = (name) ->
  for c in allClasses
    if c.name == name
      return c

getIndexedClassFromPerson = (name, index) ->
  return false if not findPerson name
  return (findPerson name).classes[index]

getSharedClasses = (name, other) ->
  if not findPerson name or not findPerson other
    console.warn "getSharedClasses encountered name:#{name}, other:#{other}, some unknown"
    return false
  else
    output = ""
    thisClasses = (findPerson name).classes
    otherClasses = (findPerson other).classes
    i = 0
    while i < 7
      if thisClasses[i] == otherClasses[i]
        output += "Period #{i+1}: #{getIndexedClassFromPerson name, i}\n"
      i++
    return output

flushJSON = () ->
  fs.writeFile "classes.json", JSON.stringify allClasses

HandlerModules =
  NewSchedule:
    RequiredParams: () ->
      buf = ["name"]
      i = 0
      while i < 7
        buf.push "classes#{i}"
        i++
      return buf
    Handle: (query, resp) ->
      if findPerson query.name
        resp.end "That person already exists"
      else
        qclasses = []
        a = 0
        while a < 7
          qclasses.push(query["classes#{a}"])
          a++
        console.error "Invalid qclasses! #{qclasses}" if qclasses.length != 7
        allClasses.push {
          name: query.name,
          classes: qclasses
        }
        flushJSON()
        console.log "New record for #{query.name}"
        resp.end "Schedule inserted successfully"
  EditSchedule:
    RequiredParams: -> ["name", "classIndex", "newClass"]
    Handle: (query, resp) ->
      if not findPerson query.name
        resp.end "Person named #{query.name} does not exist"
        return
      classIndex = parseInt query.classIndex
      if classIndex is NaN
        resp.end "classIndex (#{query.classIndex}) not an integer"
        return
      if classIndex < 0 or classIndex > 6
        resp.end "classIndex #{classIndex} out of range"
        return
      for user in allClasses
        if user.name == query.name
          user.classes[classIndex] = query.newClass
          flushJSON()
          resp.end "Classes have been updated. New classes: #{user.classes}"
          return
      resp.end "The server has an issue. Report to the owner."
  GetShared:
    RequiredParams: () -> ["name1", "name2"]
    Handle: (query, resp) ->
      sharedClasses = getSharedClasses query.name1, query.name2
      if sharedClasses == false
        resp.end "Failed to find shared classes. The most likely issue is mistaken person names."
      else
        resp.end "#{query.name1} and #{query.name2} share --\n#{sharedClasses}"
  ListUsers:
    RequiredParams: () -> []
    Handle: (query, resp) ->
      buffer = "List of users with recorded schedule --\n"
      for person in allClasses
        buffer += " - #{person.name}\n"
      resp.end buffer
  GetSummary:
    RequiredParams: () -> ["name"]
    Handle: (query, resp) ->
      if not findPerson query.name
        resp.end "#{query.name} does not exist"
      else
        buffer = "Summary of shared classes, freshly generated for #{query.name}\n-----\n"
        for person in allClasses
          if person.name != query.name
            buffer += "with #{person.name}: \n#{getSharedClasses query.name, person.name}-----\n"
        resp.end buffer
  GetAlternativeSummary:
    RequiredParams: () -> ["name"]
    Handle: (query, resp) ->
      if not findPerson query.name
        resp.end "That person cannot be found: #{query.name}"
      else
        buffer = "Classmates of #{query.name} per period --\n-----\n"
        perso = findPerson query.name
        i = 0
        while i < 7
          buffer += "Period #{i+1} (#{perso.classes[i]}) classmates:\n"
          for person in allClasses
            if person.classes[i] == perso.classes[i] and person.name != perso.name
              buffer += " - #{person.name}\n"
          buffer += "-----\n"
          i++
        resp.end buffer

serv = http.createServer (request, response) ->
  query = (url.parse request.url, true).query
  console.log "New request: #{request.url}"

  # Start new procedure
  if not query.type or query.type not in Object.keys HandlerModules
    response.end "Bad type"
  else
    for rp in HandlerModules[query.type].RequiredParams()
      if rp not in Object.keys query
        response.end "Missing required parameter for module #{query.type}: #{rp}"
        return
    HandlerModules[query.type].Handle query, response

serv.listen 8081
