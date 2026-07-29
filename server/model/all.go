package model

// All returns all schema instances.
func All() []interface{} {
	return []interface{}{
		new(TagDefinition),
		new(LabelValueColor),
		new(LabelSet),
		new(LabelSetMember),
		new(User),
		new(Device),
		new(TimeSpan),
		new(TimeSpanTag),
		new(TimeSpanTombstone),
		new(UserPreferences),
	}
}
