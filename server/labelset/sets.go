// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package labelset

import (
	"context"
	"fmt"
	"strings"

	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

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

// CreateLabelSet creates a label set at the end of the user's launcher order.
func (r *ResolverForLabelSet) CreateLabelSet(ctx context.Context, name string, symbolName string, labels []*gqlmodel.InputLabel) (*gqlmodel.LabelSet, error) {
	if strings.TrimSpace(name) == "" {
		return nil, fmt.Errorf("label set name must not be empty")
	}
	userID := auth.GetUser(ctx).ID

	position := 0
	var last model.LabelSet
	if !r.DB.Where("user_id = ?", userID).Order("position desc").First(&last).RecordNotFound() {
		position = last.Position + 1
	}

	set := model.LabelSet{
		UserID:     &userID,
		Name:       name,
		SymbolName: symbolName,
		Position:   position,
		Members:    membersFromInput(labels),
	}
	if err := r.DB.Create(&set).Error; err != nil {
		return nil, err
	}
	return toExternal(set), nil
}

// UpdateLabelSet replaces a label set's name, symbol and members.
func (r *ResolverForLabelSet) UpdateLabelSet(ctx context.Context, id int, name string, symbolName string, labels []*gqlmodel.InputLabel) (*gqlmodel.LabelSet, error) {
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
	if err := tx.Model(new(model.LabelSet)).Where("id = ?", id).
		Updates(map[string]interface{}{"name": name, "symbol_name": symbolName}).Error; err != nil {
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
	return toExternal(set), nil
}

// MoveLabelSet moves a label set to a new position (0-based) in the user's
// launcher order and returns all sets in their new order.
func (r *ResolverForLabelSet) MoveLabelSet(ctx context.Context, id int, position int) ([]*gqlmodel.LabelSet, error) {
	userID := auth.GetUser(ctx).ID

	var sets []model.LabelSet
	if err := r.DB.Where("user_id = ?", userID).Order("position").Find(&sets).Error; err != nil {
		return nil, err
	}

	fromIndex := -1
	for i, set := range sets {
		if set.ID == id {
			fromIndex = i
		}
	}
	if fromIndex == -1 {
		return nil, fmt.Errorf("label set with id %d does not exist", id)
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

	tx := r.DB.Begin()
	for i, set := range sets {
		if err := tx.Model(new(model.LabelSet)).Where("id = ?", set.ID).
			Update("position", i).Error; err != nil {
			tx.Rollback()
			return nil, err
		}
	}
	if err := tx.Commit().Error; err != nil {
		return nil, err
	}
	return r.LabelSets(ctx)
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
