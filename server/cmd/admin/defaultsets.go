// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

// Default label-set collection management: template label sets (rows with a
// nil user and the default-collection flag) that are copied to every newly
// created user. See the labelset package for the seeding logic.

package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/jinzhu/gorm"
	"primetime.tools/server/labelset"
	"primetime.tools/server/model"
)

func listDefaultSets(db *gorm.DB) {
	var sets []model.LabelSet
	if err := db.Preload("Members", func(db *gorm.DB) *gorm.DB {
		return db.Order("position")
	}).
		Where("user_id IS NULL AND default_collection = ?", true).
		Order("position").
		Find(&sets).Error; err != nil {
		fail(fmt.Sprintf("list default sets: %s", err))
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "ID\tPOS\tNAME\tSYMBOL\tLABELS")
	for _, set := range sets {
		labels := make([]string, 0, len(set.Members))
		for _, member := range set.Members {
			labels = append(labels, member.Key+"="+member.StringValue)
		}
		fmt.Fprintf(w, "%d\t%d\t%s\t%s\t%s\n",
			set.ID, set.Position, set.Name, set.SymbolName, strings.Join(labels, ","))
	}
	w.Flush()
}

func addDefaultSet(db *gorm.DB, args []string) {
	fs := flag.NewFlagSet("add-default-set", flag.ExitOnError)
	name := fs.String("name", "", "set name (required)")
	symbol := fs.String("symbol", "tag", "SF Symbol name for the launcher card")
	labelsArg := fs.String("labels", "", "comma-separated key=value members, in order")
	parse(fs, args)
	requireFlags(fs, map[string]string{"name": *name})

	members, err := parseLabels(*labelsArg)
	if err != nil {
		fail(err.Error())
	}

	position := 0
	last := model.LabelSet{}
	if !db.Where("user_id IS NULL AND default_collection = ?", true).
		Order("position desc").First(&last).RecordNotFound() {
		position = last.Position + 1
	}

	set := model.LabelSet{
		Name:              *name,
		SymbolName:        *symbol,
		Position:          position,
		DefaultCollection: true,
		Members:           members,
	}
	if err := db.Create(&set).Error; err != nil {
		fail(fmt.Sprintf("add default set: %s", err))
	}
	fmt.Printf("added default set %q (id=%d, %d labels)\n", set.Name, set.ID, len(set.Members))
}

func removeDefaultSet(db *gorm.DB, args []string) {
	fs := flag.NewFlagSet("remove-default-set", flag.ExitOnError)
	id := fs.Int("id", 0, "set id (required, see list-default-sets)")
	parse(fs, args)
	if *id == 0 {
		fmt.Fprintln(os.Stderr, "missing required flag -id")
		fs.Usage()
		os.Exit(2)
	}

	set := model.LabelSet{}
	if db.Where("user_id IS NULL AND default_collection = ? AND id = ?", true, *id).
		Find(&set).RecordNotFound() {
		fail(fmt.Sprintf("default set with id %d does not exist", *id))
	}
	if err := db.Delete(new(model.LabelSet), "id = ?", *id).Error; err != nil {
		fail(fmt.Sprintf("remove default set: %s", err))
	}
	fmt.Printf("removed default set %q (id=%d)\n", set.Name, set.ID)
}

func seedUser(db *gorm.DB, args []string) {
	fs := flag.NewFlagSet("seed-user", flag.ExitOnError)
	name := fs.String("name", "", "user name (required)")
	parse(fs, args)
	requireFlags(fs, map[string]string{"name": *name})

	user := new(model.User)
	if db.Where("name = ?", *name).Find(user).RecordNotFound() {
		fail(fmt.Sprintf("user %q does not exist", *name))
	}
	if err := labelset.SeedDefaultLabelSets(db, user.ID); err != nil {
		fail(fmt.Sprintf("seed user: %s", err))
	}
	fmt.Printf("seeded user %q with the default label-set collection\n", user.Name)
}

// parseLabels parses "key=value,key2=value2" into ordered members. Empty
// input yields no members; a bare "key" (no =) gets an empty value.
func parseLabels(input string) ([]model.LabelSetMember, error) {
	members := []model.LabelSetMember{}
	if strings.TrimSpace(input) == "" {
		return members, nil
	}
	for i, pair := range strings.Split(input, ",") {
		key, value, _ := strings.Cut(strings.TrimSpace(pair), "=")
		if key == "" {
			return nil, fmt.Errorf("invalid -labels entry %q (want key=value)", pair)
		}
		members = append(members, model.LabelSetMember{
			Position:    i,
			Key:         key,
			StringValue: value,
		})
	}
	return members, nil
}
