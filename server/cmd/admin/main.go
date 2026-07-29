// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

// Command admin is the PrimeTime server admin CLI. It covers the user
// administration the (removed) traggo web UI used to provide: creating
// users, resetting passwords, and listing users/devices.
//
// It operates directly on the server database and reads the same TRAGGO_*
// configuration (environment variables or .env files) as the server, so it
// can be run alongside a server pointed at the same database.
//
// This file is new PrimeTime code (not derived from a traggo source file),
// licensed AGPL-3.0-or-later; it links against the GPL-3.0 traggo-derived
// packages of this tree (a combination GPLv3 section 13 permits — see NOTICE).
package main

import (
	"flag"
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/jinzhu/gorm"
	"github.com/rs/zerolog"
	"primetime.tools/server/config"
	"primetime.tools/server/database"
	"primetime.tools/server/logger"
	"primetime.tools/server/model"
	"primetime.tools/server/user/password"
)

func usage() {
	fmt.Fprintf(os.Stderr, `usage: admin <command> [flags]

commands:
  create-user     -name <name> -pass <pass> [-admin]
  reset-password  -name <name> -pass <pass>
  list-users
  list-devices    [-user <name>]

Database and password-strength settings come from the same TRAGGO_*
configuration as the server (environment variables or .env files).
`)
	os.Exit(2)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}

	conf, errs := config.Get()
	logger.Init(zerolog.WarnLevel)
	for _, err := range errs {
		if err.Level == zerolog.FatalLevel || err.Level == zerolog.PanicLevel {
			fail(err.Msg)
		}
	}

	db, err := database.New(conf.DatabaseDialect, conf.DatabaseConnection)
	if err != nil {
		fail(fmt.Sprintf("connect to database: %s", err))
	}
	defer db.Close()

	switch os.Args[1] {
	case "create-user":
		createUser(db, conf, os.Args[2:])
	case "reset-password":
		resetPassword(db, conf, os.Args[2:])
	case "list-users":
		listUsers(db)
	case "list-devices":
		listDevices(db, os.Args[2:])
	case "-h", "--help", "help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n", os.Args[1])
		usage()
	}
}

func createUser(db *gorm.DB, conf config.Config, args []string) {
	fs := flag.NewFlagSet("create-user", flag.ExitOnError)
	name := fs.String("name", "", "user name (required)")
	pass := fs.String("pass", "", "password (required)")
	admin := fs.Bool("admin", false, "grant admin rights")
	parse(fs, args)
	requireFlags(fs, map[string]string{"name": *name, "pass": *pass})

	if !db.Where("name = ?", *name).Find(new(model.User)).RecordNotFound() {
		fail(fmt.Sprintf("user %q already exists", *name))
	}
	user := model.User{
		Name:  *name,
		Pass:  password.CreatePassword(*pass, conf.PassStrength),
		Admin: *admin,
	}
	if err := db.Create(&user).Error; err != nil {
		fail(fmt.Sprintf("create user: %s", err))
	}
	fmt.Printf("created user %q (id=%d admin=%t)\n", user.Name, user.ID, user.Admin)
}

func resetPassword(db *gorm.DB, conf config.Config, args []string) {
	fs := flag.NewFlagSet("reset-password", flag.ExitOnError)
	name := fs.String("name", "", "user name (required)")
	pass := fs.String("pass", "", "new password (required)")
	parse(fs, args)
	requireFlags(fs, map[string]string{"name": *name, "pass": *pass})

	user := new(model.User)
	if db.Where("name = ?", *name).Find(user).RecordNotFound() {
		fail(fmt.Sprintf("user %q does not exist", *name))
	}
	user.Pass = password.CreatePassword(*pass, conf.PassStrength)
	if err := db.Save(user).Error; err != nil {
		fail(fmt.Sprintf("reset password: %s", err))
	}
	fmt.Printf("password reset for user %q (id=%d)\n", user.Name, user.ID)
}

func listUsers(db *gorm.DB) {
	var users []model.User
	if err := db.Order("id").Find(&users).Error; err != nil {
		fail(fmt.Sprintf("list users: %s", err))
	}
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "ID\tNAME\tADMIN")
	for _, u := range users {
		fmt.Fprintf(w, "%d\t%s\t%t\n", u.ID, u.Name, u.Admin)
	}
	w.Flush()
}

func listDevices(db *gorm.DB, args []string) {
	fs := flag.NewFlagSet("list-devices", flag.ExitOnError)
	userName := fs.String("user", "", "only devices of this user")
	parse(fs, args)

	query := db.Order("id")
	if *userName != "" {
		user := new(model.User)
		if db.Where("name = ?", *userName).Find(user).RecordNotFound() {
			fail(fmt.Sprintf("user %q does not exist", *userName))
		}
		query = query.Where("user_id = ?", user.ID)
	}
	var devices []model.Device
	if err := query.Find(&devices).Error; err != nil {
		fail(fmt.Sprintf("list devices: %s", err))
	}

	users := map[int]string{}
	var all []model.User
	db.Find(&all)
	for _, u := range all {
		users[u.ID] = u.Name
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "ID\tUSER\tNAME\tTYPE\tCREATED\tACTIVE")
	for _, d := range devices {
		fmt.Fprintf(w, "%d\t%s\t%s\t%s\t%s\t%s\n",
			d.ID, users[d.UserID], d.Name, d.Type,
			d.CreatedAt.Format("2006-01-02 15:04"),
			d.ActiveAt.Format("2006-01-02 15:04"))
	}
	w.Flush()
}

func parse(fs *flag.FlagSet, args []string) {
	_ = fs.Parse(args) // ExitOnError: never returns an error
}

func requireFlags(fs *flag.FlagSet, required map[string]string) {
	for flagName, value := range required {
		if value == "" {
			fmt.Fprintf(os.Stderr, "missing required flag -%s\n", flagName)
			fs.Usage()
			os.Exit(2)
		}
	}
}

func fail(msg string) {
	fmt.Fprintln(os.Stderr, "error:", msg)
	os.Exit(1)
}
