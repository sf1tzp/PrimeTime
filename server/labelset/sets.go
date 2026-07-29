// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package labelset

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jinzhu/gorm"
	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// syncNow is the clock for sync timestamps (UpdatedAtUTC): whole seconds so
// values round-trip through RFC3339 exactly. Overridable in tests.
var syncNow = func() time.Time { return time.Now().UTC().Truncate(time.Second) }

// LabelSets returns the current user's label sets in launcher order.
func (r *ResolverForLabelSet) LabelSets(ctx context.Context) ([]*gqlmodel.LabelSet, error) {
	userID := auth.GetUser(ctx).ID
	var sets []model.LabelSet
	find := preloadMembers(r.DB).
		Where("user_id = ?", userID).
		Order("position").
		Find(&sets)
	result := []*gqlmodel.LabelSet{}
	for _, set := range sets {
		result = append(result, toExternal(set))
	}
	return result, find.Error
}

// CreateLabelSet creates a label set — at the end of the user's launcher
// order, or at `position` (0-based, clamped) when given.
func (r *ResolverForLabelSet) CreateLabelSet(ctx context.Context, name string, symbolName string, labels []*gqlmodel.InputLabel, position *int) (*gqlmodel.LabelSet, error) {
	if strings.TrimSpace(name) == "" {
		return nil, fmt.Errorf("label set name must not be empty")
	}
	userID := auth.GetUser(ctx).ID

	appendPosition := 0
	var last model.LabelSet
	if !r.DB.Where("user_id = ?", userID).Order("position desc").First(&last).RecordNotFound() {
		appendPosition = last.Position + 1
	}

	set := model.LabelSet{
		UserID:       &userID,
		Name:         name,
		SymbolName:   symbolName,
		Position:     appendPosition,
		Members:      membersFromInput(labels),
		UpdatedAtUTC: syncNow(),
	}
	if err := r.DB.Create(&set).Error; err != nil {
		return nil, err
	}
	if position != nil && *position != set.Position {
		if err := move(r.DB, userID, set.ID, *position); err != nil {
			return nil, err
		}
		set.Position = *position
	}
	return toExternal(set), nil
}

// UpdateLabelSet replaces a label set's name, symbol and members — and,
// when `position` is given, moves it there (0-based, clamped).
func (r *ResolverForLabelSet) UpdateLabelSet(ctx context.Context, id int, name string, symbolName string, labels []*gqlmodel.InputLabel, position *int) (*gqlmodel.LabelSet, error) {
	if strings.TrimSpace(name) == "" {
		return nil, fmt.Errorf("label set name must not be empty")
	}
	userID := auth.GetUser(ctx).ID

	set := model.LabelSet{}
	if r.DB.Where("user_id = ? AND id = ?", userID, id).Find(&set).RecordNotFound() {
		return nil, fmt.Errorf("label set with id %d does not exist", id)
	}

	tx := r.DB.Begin()
	set.Name = name
	set.SymbolName = symbolName
	set.UpdatedAtUTC = syncNow()
	if err := tx.Model(new(model.LabelSet)).Where("id = ?", id).
		Updates(map[string]interface{}{
			"name":           name,
			"symbol_name":    symbolName,
			"updated_at_utc": set.UpdatedAtUTC,
		}).Error; err != nil {
		tx.Rollback()
		return nil, err
	}
	if err := tx.Where("label_set_id = ?", id).Delete(new(model.LabelSetMember)).Error; err != nil {
		tx.Rollback()
		return nil, err
	}
	set.Members = membersFromInput(labels)
	for i := range set.Members {
		set.Members[i].LabelSetID = id
		if err := tx.Create(&set.Members[i]).Error; err != nil {
			tx.Rollback()
			return nil, err
		}
	}
	if err := tx.Commit().Error; err != nil {
		return nil, err
	}
	if position != nil && *position != set.Position {
		if err := move(r.DB, userID, id, *position); err != nil {
			return nil, err
		}
		set.Position = *position
	}
	return toExternal(set), nil
}

// MoveLabelSet moves a label set to a new position (0-based) in the user's
// launcher order and returns all sets in their new order.
func (r *ResolverForLabelSet) MoveLabelSet(ctx context.Context, id int, position int) ([]*gqlmodel.LabelSet, error) {
	userID := auth.GetUser(ctx).ID
	if err := move(r.DB, userID, id, position); err != nil {
		return nil, err
	}
	return r.LabelSets(ctx)
}

// move repositions a set (0-based, clamped) and renumbers the others. Only
// sets whose position actually changes get their sync timestamp bumped, so
// a reorder doesn't spuriously win last-writer-wins against real edits made
// elsewhere.
func move(db *gorm.DB, userID int, id int, position int) error {
	var sets []model.LabelSet
	if err := db.Where("user_id = ?", userID).Order("position").Find(&sets).Error; err != nil {
		return err
	}

	fromIndex := -1
	for i, set := range sets {
		if set.ID == id {
			fromIndex = i
		}
	}
	if fromIndex == -1 {
		return fmt.Errorf("label set with id %d does not exist", id)
	}
	if position < 0 {
		position = 0
	}
	if position > len(sets)-1 {
		position = len(sets) - 1
	}

	moved := sets[fromIndex]
	sets = append(sets[:fromIndex], sets[fromIndex+1:]...)
	sets = append(sets[:position], append([]model.LabelSet{moved}, sets[position:]...)...)

	now := syncNow()
	tx := db.Begin()
	for i, set := range sets {
		if set.Position == i {
			continue
		}
		if err := tx.Model(new(model.LabelSet)).Where("id = ?", set.ID).
			Updates(map[string]interface{}{
				"position":       i,
				"updated_at_utc": now,
			}).Error; err != nil {
			tx.Rollback()
			return err
		}
	}
	return tx.Commit().Error
}

// RemoveLabelSet deletes a label set (its members cascade).
func (r *ResolverForLabelSet) RemoveLabelSet(ctx context.Context, id int) (*gqlmodel.LabelSet, error) {
	userID := auth.GetUser(ctx).ID

	set := model.LabelSet{}
	if preloadMembers(r.DB).Where("user_id = ? AND id = ?", userID, id).Find(&set).RecordNotFound() {
		return nil, fmt.Errorf("label set with id %d does not exist", id)
	}

	if err := r.DB.Delete(new(model.LabelSet), "id = ?", id).Error; err != nil {
		return nil, err
	}
	return toExternal(set), nil
}
