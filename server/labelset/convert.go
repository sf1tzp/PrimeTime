// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package labelset

import (
	"github.com/jinzhu/gorm"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// toExternal converts a label set (with members) to its external form.
// Members are expected to be loaded in position order.
func toExternal(set model.LabelSet) *gqlmodel.LabelSet {
	labels := []*gqlmodel.Label{}
	for _, member := range set.Members {
		labels = append(labels, &gqlmodel.Label{
			Key:   member.Key,
			Value: member.StringValue,
		})
	}
	return &gqlmodel.LabelSet{
		ID:         set.ID,
		Name:       set.Name,
		SymbolName: set.SymbolName,
		Labels:     labels,
	}
}

// membersFromInput converts input labels to member rows in input order.
func membersFromInput(labels []*gqlmodel.InputLabel) []model.LabelSetMember {
	members := make([]model.LabelSetMember, 0, len(labels))
	for i, label := range labels {
		members = append(members, model.LabelSetMember{
			Position:    i,
			Key:         label.Key,
			StringValue: label.Value,
		})
	}
	return members
}

// preloadMembers preloads set members in position order.
func preloadMembers(db *gorm.DB) *gorm.DB {
	return db.Preload("Members", func(db *gorm.DB) *gorm.DB {
		return db.Order("position")
	})
}
