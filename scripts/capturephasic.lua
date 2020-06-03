function createFilledPodPhasic(pet)
  return {
      name = "filledcapturepodphasic",
      count = 1,
      parameters = {
          description = pet.description,
          tooltipFields = {
              subtitle = pet.name or "Unknown",
              objectImage = pet.portrait
            },
          podUuid = sb.makeUuid(),
          collectablesOnPickup = pet.collectables,
          pets = {pet}
        }
    }
end
