package main

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

var (
	deviceRe = regexp.MustCompile(`^(\d+):\s+(\w+)\s+(.*)$`)
	fieldRe  = regexp.MustCompile(`([a-z-]+)\s+((?:\{[^}]*\})|"(?:[^"\\]|\\.)*"|\S+)`)
)

type device struct {
	ID          string
	Action      string
	Rule        string
	USBID       string
	Name        string
	Serial      string
	ViaPort     string
	ConnectType string
	Hash        string
	Interfaces  []string
}

type whitelist struct {
	Devices []struct {
		Label string `json:"label"`
		Rule  string `json:"rule"`
	} `json:"devices"`
}

type persistedRules struct {
	Devices []struct {
		UUID  string `json:"uuid,omitempty"`
		Label string `json:"label"`
		Risk  string `json:"risk,omitempty"`
		Rule  string `json:"rule"`
	} `json:"devices"`
}

type cfg struct {
	MaxBlockedScan      int
	MaxPromptsPerCycle  int
	PromptCooldown      time.Duration
	PortPromptCooldown  time.Duration
	QueuePoll           time.Duration
	QueueDormantBacklog int
	QueueDormantSleep   time.Duration
	SerialQueueMode     bool
	DisableDockGrouping bool
	AutoPrompt          bool
	AutoBlockStorage    bool
	Popups              bool
	StateDir            string
	AllowedPath         string
	WhitelistPath       string
	BlacklistPath       string
}

type cliOptions struct {
	Watch     bool
	Queue     bool
	Review    bool
	Audit     bool
	ApproveID string
	Permanent bool
	Release   string
	Help      bool
}

func main() {
	c := loadCfg()
	wl := loadWhitelist(c.WhitelistPath)
	trusted := map[string]string{}
	for _, item := range wl.Devices {
		trusted[item.Rule] = item.Label
	}

	opts, err := parseCLI()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		printUsage(os.Stderr)
		os.Exit(2)
	}
	if opts.Help {
		printUsage(os.Stdout)
		return
	}

	switch {
	case opts.Watch:
		err = watch(c, trusted)
	case opts.Queue:
		err = printQueue(c, trusted)
	case opts.Audit:
		err = audit(c)
	case opts.ApproveID != "":
		err = approveByID(c, opts.ApproveID, opts.Permanent)
	case opts.Release != "":
		err = releaseQueued(c, opts.Release)
	case opts.Review || noAction(opts):
		err = reviewOnce(c, trusted)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func parseCLI() (cliOptions, error) {
	var opts cliOptions
	fs := flag.NewFlagSet("usb-guard", flag.ContinueOnError)
	fs.SetOutput(new(bytes.Buffer))
	fs.BoolVar(&opts.Watch, "watch", false, "watch blocked devices and prompt/queue them")
	fs.BoolVar(&opts.Queue, "queue", false, "show blocked queue with ids and states")
	fs.BoolVar(&opts.Review, "review", false, "review blocked devices once")
	fs.BoolVar(&opts.Audit, "audit", false, "print usbguard and lsusb audit info")
	fs.StringVar(&opts.ApproveID, "approve", "", "approve a blocked USBGuard device id")
	fs.BoolVar(&opts.Permanent, "permanent", false, "use with --approve to append a persistent allow rule")
	fs.StringVar(&opts.Release, "release", "", "release queued/denied state for a blocked id, or use all")
	fs.StringVar(&opts.Release, "r", "", "release queued/denied state for a blocked id")
	fs.BoolVar(&opts.Help, "help", false, "show help")
	if err := fs.Parse(normalizeArgs(os.Args[1:])); err != nil {
		return opts, err
	}
	actions := 0
	for _, enabled := range []bool{opts.Watch, opts.Queue, opts.Review, opts.Audit, opts.ApproveID != "", opts.Release != ""} {
		if enabled {
			actions++
		}
	}
	if actions > 1 {
		return opts, fmt.Errorf("choose only one primary action at a time")
	}
	if opts.Permanent && opts.ApproveID == "" {
		return opts, fmt.Errorf("--permanent only makes sense with --approve")
	}
	return opts, nil
}

func noAction(opts cliOptions) bool {
	return !opts.Watch && !opts.Queue && !opts.Review && !opts.Audit && opts.ApproveID == "" && opts.Release == ""
}

func printUsage(w *os.File) {
	fmt.Fprintln(w, "usb-guard - unified USBGuard review and queue control")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "Usage:")
	fmt.Fprintln(w, "  usb-guard --review")
	fmt.Fprintln(w, "  usb-guard --watch")
	fmt.Fprintln(w, "  usb-guard --queue")
	fmt.Fprintln(w, "  usb-guard --approve ID [--permanent]")
	fmt.Fprintln(w, "  usb-guard --release UUID")
	fmt.Fprintln(w, "  usb-guard --release")
	fmt.Fprintln(w, "  usb-guard --audit")
}

func normalizeArgs(args []string) []string {
	out := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "--release" || arg == "-r" {
			if i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") {
				out = append(out, "--release="+args[i+1])
				i++
				continue
			}
			out = append(out, "--release=__prompt__")
			continue
		}
		out = append(out, arg)
	}
	return out
}

func loadCfg() cfg {
	stateHome := strings.TrimSpace(os.Getenv("XDG_STATE_HOME"))
	if stateHome == "" {
		home, _ := os.UserHomeDir()
		stateHome = filepath.Join(home, ".local", "state")
	}
	runtimeDir := strings.TrimSpace(os.Getenv("XDG_RUNTIME_DIR"))
	if runtimeDir == "" {
		runtimeDir = stateHome
	}
	return cfg{
		MaxBlockedScan:      envInt("USBGUARD_MAX_BLOCKED_SCAN", 64),
		MaxPromptsPerCycle:  envInt("USBGUARD_MAX_PROMPTS_PER_CYCLE", 1),
		PromptCooldown:      envSeconds("USBGUARD_PROMPT_COOLDOWN_SECONDS", 2),
		PortPromptCooldown:  envSeconds("USBGUARD_PORT_PROMPT_COOLDOWN_SECONDS", 3),
		QueuePoll:           envSeconds("USBGUARD_QUEUE_POLL_SECONDS", 2),
		QueueDormantBacklog: envInt("USBGUARD_QUEUE_DORMANT_BACKLOG", 12),
		QueueDormantSleep:   envSeconds("USBGUARD_QUEUE_DORMANT_SLEEP_SECONDS", 4),
		SerialQueueMode:     envBool("USBGUARD_SERIAL_QUEUE_MODE", true),
		DisableDockGrouping: envBool("USBGUARD_DISABLE_DOCK_GROUPING", false),
		AutoPrompt:          envBool("USBGUARD_REVIEW_AUTO_PROMPT", true),
		AutoBlockStorage:    envBool("USBGUARD_REVIEW_AUTO_BLOCK_STORAGE", true),
		Popups:              envBool("USBGUARD_REVIEW_POPUPS", true),
		StateDir:            filepath.Join(stateHome, "usbguard-review"),
		AllowedPath:         firstNonEmpty(strings.TrimSpace(os.Getenv("USBGUARD_PERSISTENT_ALLOWED_JSON")), filepath.Join(runtimeDir, "usbguard-review", "allowed.json")),
		WhitelistPath:       strings.TrimSpace(os.Getenv("USBGUARD_WHITELIST_JSON")),
		BlacklistPath:       firstNonEmpty(strings.TrimSpace(os.Getenv("USBGUARD_PERSISTENT_BLACKLIST_JSON")), filepath.Join(stateHome, "usbguard-review", "blacklist.json")),
	}
}

func reviewOnce(c cfg, trusted map[string]string) error {
	devices, err := blockedDevices(c)
	if err != nil {
		return err
	}
	blacklist := loadPersistedRules(c.BlacklistPath)
	allowedList := loadPersistedRules(c.AllowedPath)
	if len(devices) == 0 {
		fmt.Println("No blocked USB devices in queue.")
		return nil
	}

	seen := map[string]bool{}
	for _, dev := range devices {
		key := deviceKey(dev)
		if seen[key] {
			continue
		}
		if label, ok := blacklistLabelForRule(allowedList, "allow "+dev.Rule); ok {
			if err := approve(c, dev, false); err == nil {
				fmt.Printf("Auto-approved (persistent): %s\n", firstNonEmpty(label, displayName(dev)))
				seen[key] = true
				continue
			}
		}
		group := dockGroup(c, devices, dev)
		if len(group) > 1 {
			decision, selected, err := promptGroup(c, group)
			if err != nil {
				return err
			}
			if decision == "skip" {
				continue
			}
			selectedSet := sliceToSet(selected)
			for _, item := range group {
				seen[deviceKey(item)] = true
				if !selectedSet[item.ID] {
					fmt.Printf("Left blocked: %s\n", displayName(item))
					continue
				}
				switch decision {
				case "approve-once", "approve-permanently":
					if err := approve(c, item, decision == "approve-permanently"); err != nil {
						return err
					}
					fmt.Printf("%s: %s\n", approvalPrefix(decision), displayName(item))
				case "deny-permanently":
					if err := persistBlock(c, item, blacklist); err != nil {
						return err
					}
					fmt.Printf("Blocked permanently: %s\n", displayName(item))
				default:
					fmt.Printf("Left blocked: %s\n", displayName(item))
				}
			}
			continue
		}

		decision, err := promptSingle(c, trusted, dev)
		if err != nil {
			return err
		}
		if decision == "skip" {
			continue
		}
		seen[key] = true
		switch decision {
		case "approve-once", "approve-permanently":
			if err := approve(c, dev, decision == "approve-permanently"); err != nil {
				return err
			}
			fmt.Printf("%s: %s\n", approvalPrefix(decision), displayName(dev))
		case "deny-permanently":
			if err := persistBlock(c, dev, blacklist); err != nil {
				return err
			}
			fmt.Printf("Blocked permanently: %s\n", displayName(dev))
		default:
			fmt.Printf("Left blocked: %s\n", displayName(dev))
		}
	}
	return nil
}

func watch(c cfg, trusted map[string]string) error {
	seenDir := filepath.Join(c.StateDir, "seen")
	if err := os.MkdirAll(seenDir, 0o755); err != nil {
		return err
	}

	lastPromptByPort := map[string]time.Time{}
	var lastPrompt time.Time

	for {
		devices, err := blockedDevices(c)
		if err != nil {
			notify("USBGuard", "Failed to read blocked USB devices")
			time.Sleep(c.QueuePoll)
			continue
		}
		blacklist := loadPersistedRules(c.BlacklistPath)
		allowedList := loadPersistedRules(c.AllowedPath)

		active := map[string]bool{}
		grouped := map[string]bool{}
		queued := []string{}
		prompts := 0
		now := time.Now()

		for _, dev := range devices {
			key := deviceKey(dev)
			active[key] = true
			if grouped[key] {
				continue
			}
			marker := filepath.Join(seenDir, key)
			if _, err := os.Stat(marker); err == nil {
				continue
			}

			if label, ok := blacklistLabelFor(blacklist, dev); ok {
				_ = writeMarker(marker, "deny-permanently")
				_ = blockDevice(dev)
				notify("USBGuard", fmt.Sprintf("Persistently blocked device: %s", firstNonEmpty(label, displayName(dev))))
				continue
			}

			if label, ok := blacklistLabelForRule(allowedList, "allow "+dev.Rule); ok {
				if err := approve(c, dev, false); err == nil {
					_ = writeMarker(marker, "allowed-permanently-transient")
					notify("USBGuard", fmt.Sprintf("Auto-approved (persistent): %s", firstNonEmpty(label, displayName(dev))))
					continue
				}
			}

			if label, ok := trusted[dev.Rule]; ok {
				if err := approve(c, dev, false); err == nil {
					_ = writeMarker(marker, "trusted-auto-allow")
					notify("USBGuard", fmt.Sprintf("Auto-approved trusted device: %s", firstNonEmpty(label, displayName(dev))))
					continue
				}
			}

			if c.AutoBlockStorage && shouldAutoQuarantineStorage(dev) {
				uuid, err := quarantineStorageDevice(c, dev, blacklist)
				if err == nil {
					_ = writeMarker(marker, "storage-quarantined")
					notify("USBGuard", fmt.Sprintf("Storage device quarantined: %s [%s]", displayName(dev), uuid))
					continue
				}
			}

			// Check prompt limit only for interactive prompts, not auto-approvals
			if prompts >= c.MaxPromptsPerCycle {
				grouped[key] = true
				queued = append(queued, queueLabel(dev))
				continue
			}

			if !lastPrompt.IsZero() && now.Sub(lastPrompt) < c.PromptCooldown {
				continue
			}
			token := rootPortToken(dev)
			if token != "" {
				if ts, ok := lastPromptByPort[token]; ok && now.Sub(ts) < c.PortPromptCooldown {
					continue
				}
			}

			group := dockGroup(c, devices, dev)
			if !c.AutoPrompt || !canPromptGraphically(c) {
				for _, item := range group {
					grouped[deviceKey(item)] = true
					_ = writeMarker(filepath.Join(seenDir, deviceKey(item)), "queued")
					queued = append(queued, queueLabel(item))
				}
			} else if len(group) > 1 {
				decision, selected, err := promptGroup(c, group)
				if err != nil {
					decision = "skip"
				}
				if decision == "skip" {
					continue
				}
				selectedSet := sliceToSet(selected)
				for _, item := range group {
					grouped[deviceKey(item)] = true
					groupMarker := filepath.Join(seenDir, deviceKey(item))
					if selectedSet[item.ID] {
						_ = writeMarker(groupMarker, decision)
						switch decision {
						case "approve-once", "approve-permanently":
							if err := approve(c, item, decision == "approve-permanently"); err == nil {
								notify("USBGuard", fmt.Sprintf("%s: %s", approvalPrefix(decision), displayName(item)))
							}
						case "deny-permanently":
							if err := persistBlock(c, item, blacklist); err == nil {
								notify("USBGuard", fmt.Sprintf("Blocked permanently: %s", displayName(item)))
							}
						}
					} else {
						_ = writeMarker(groupMarker, "deny")
					}
				}
			} else {
				decision, err := promptSingle(c, trusted, dev)
				if err != nil {
					decision = "skip"
				}
				if decision == "skip" {
					continue
				}
				_ = writeMarker(marker, decision)
				switch decision {
				case "approve-once", "approve-permanently":
					if err := approve(c, dev, decision == "approve-permanently"); err == nil {
						notify("USBGuard", fmt.Sprintf("%s: %s", approvalPrefix(decision), displayName(dev)))
					}
				case "deny-permanently":
					if err := persistBlock(c, dev, blacklist); err == nil {
						notify("USBGuard", fmt.Sprintf("Blocked permanently: %s", displayName(dev)))
					}
				default:
					notify("USBGuard", fmt.Sprintf("Kept blocked: %s", displayName(dev)))
				}
			}

			if token != "" {
				lastPromptByPort[token] = now
			}
			lastPrompt = now
			prompts++
			if c.SerialQueueMode {
				break
			}
		}

		if len(queued) > 0 {
			notify("USBGuard", fmt.Sprintf("Queued %d blocked device(s): %s", len(queued), summarizeNames(queued)))
		}
		if err := cleanupSeenDir(seenDir, active); err != nil {
			return err
		}

		sleepFor := c.QueuePoll
		if len(devices) >= c.QueueDormantBacklog && sleepFor < c.QueueDormantSleep {
			sleepFor = c.QueueDormantSleep
		}
		time.Sleep(sleepFor)
	}
}

func printQueue(c cfg, trusted map[string]string) error {
	devices, err := blockedDevices(c)
	if err != nil {
		return err
	}
	if len(devices) == 0 {
		fmt.Println("No blocked USB devices in queue.")
		return nil
	}
	fmt.Printf("%-4s %-18s %-8s %-18s %s\n", "ID", "STATE", "RISK", "PORT", "NAME")
	for _, dev := range devices {
		state := markerState(filepath.Join(c.StateDir, "seen", deviceKey(dev)))
		if state == "" {
			state = "new"
		}
		name := queueLabel(dev)
		if label := trusted[dev.Rule]; label != "" {
			name = fmt.Sprintf("%s [%s]", name, label)
		}
		fmt.Printf(
			"%-4s %-18s %-17s %-18s %s\n",
			dev.ID,
			state,
			colorizeRiskLabel(riskLevel(dev)),
			firstNonEmpty(dev.ViaPort, "-"),
			name,
		)
	}
	return nil
}

func audit(c cfg) error {
	fmt.Println("== usbguard devices ==")
	if out, err := run("usbguard", "list-devices"); err == nil {
		fmt.Print(out)
	} else {
		return err
	}
	fmt.Println()
	fmt.Println("== blocked usbguard devices ==")
	if out, err := run("usbguard", "list-devices", "-b"); err == nil {
		fmt.Print(out)
	}
	fmt.Println()
	fmt.Println("== repo whitelist ==")
	if c.WhitelistPath != "" {
		data, err := os.ReadFile(c.WhitelistPath)
		if err == nil {
			fmt.Print(string(data))
		}
	}
	fmt.Println()
	fmt.Println("== lsusb ==")
	if out, err := run("lsusb"); err == nil {
		fmt.Print(out)
	}
	return nil
}

func approveByID(c cfg, id string, permanent bool) error {
	dev, err := blockedDeviceByID(c, id)
	if err != nil {
		return err
	}
	if err := approve(c, dev, permanent); err != nil {
		return err
	}
	marker := filepath.Join(c.StateDir, "seen", deviceKey(dev))
	state := "approve-once"
	if permanent {
		state = "approve-permanently"
	}
	_ = writeMarker(marker, state)
	fmt.Printf("%s: %s\n", approvalPrefix(state), displayName(dev))
	return nil
}

func releaseQueued(c cfg, target string) error {
	seenDir := filepath.Join(c.StateDir, "seen")
	if target == "__prompt__" {
		if canPromptGraphically(c) {
			return promptReleasePersistentBlocksYad(c)
		}
		return promptReleasePersistentBlocksCLI(c)
	}
	released, err := releasePersistentBlockByUUID(c, target)
	if err != nil {
		return err
	}
	if !released {
		return fmt.Errorf("no persistent blocked USB device with uuid %s", target)
	}
	entries, err := os.ReadDir(seenDir)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	_ = entries
	fmt.Printf("Released persistent block %s back into the review queue.\n", target)
	return nil
}

func blockedDeviceByID(c cfg, id string) (device, error) {
	devices, err := blockedDevices(c)
	if err != nil {
		return device{}, err
	}
	for _, dev := range devices {
		if dev.ID == id {
			return dev, nil
		}
	}
	return device{}, fmt.Errorf("no blocked USBGuard device with id %s", id)
}

func blockedDevices(c cfg) ([]device, error) {
	out, err := run("usbguard", "list-devices", "-b")
	if err != nil {
		var exitErr *exec.ExitError
		if !errors.As(err, &exitErr) {
			return nil, err
		}
	}

	devices := []device{}
	scanner := bufio.NewScanner(strings.NewReader(out))
	for scanner.Scan() {
		dev, ok := parseRuleLine(scanner.Text())
		if ok {
			devices = append(devices, dev)
		}
		if len(devices) >= c.MaxBlockedScan {
			break
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	sort.Slice(devices, func(i, j int) bool {
		li, _ := strconv.Atoi(devices[i].ID)
		lj, _ := strconv.Atoi(devices[j].ID)
		return li < lj
	})
	return devices, nil
}

func parseRuleLine(line string) (device, bool) {
	m := deviceRe.FindStringSubmatch(strings.TrimSpace(line))
	if m == nil {
		return device{}, false
	}
	fields := map[string]string{}
	for _, part := range fieldRe.FindAllStringSubmatch(m[3], -1) {
		value := part[2]
		if strings.HasPrefix(value, "\"") && strings.HasSuffix(value, "\"") {
			value = strings.Trim(value, "\"")
		}
		fields[part[1]] = value
	}

	interfaces := []string{}
	switch value := fields["with-interface"]; {
	case strings.HasPrefix(value, "{") && strings.HasSuffix(value, "}"):
		interfaces = strings.Fields(strings.Trim(value, "{}"))
	case value != "":
		interfaces = []string{value}
	}

	return device{
		ID:          m[1],
		Action:      m[2],
		Rule:        m[3],
		USBID:       fields["id"],
		Name:        fields["name"],
		Serial:      fields["serial"],
		ViaPort:     fields["via-port"],
		ConnectType: fields["with-connect-type"],
		Hash:        fields["hash"],
		Interfaces:  interfaces,
	}, true
}

func loadWhitelist(path string) whitelist {
	if path == "" {
		return whitelist{}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return whitelist{}
	}
	var wl whitelist
	if err := json.Unmarshal(data, &wl); err != nil {
		return whitelist{}
	}
	return wl
}

func promptSingle(c cfg, trusted map[string]string, dev device) (string, error) {
	if canPromptGraphically(c) {
		return promptSingleYad(trusted, dev)
	}
	return promptSingleCLI(trusted, dev)
}

func promptGroup(c cfg, group []device) (string, []string, error) {
	if canPromptGraphically(c) {
		return promptGroupYad(group)
	}
	return promptGroupCLI(group)
}

func promptSingleCLI(trusted map[string]string, dev device) (string, error) {
	reader := bufio.NewReader(os.Stdin)
	for {
		fmt.Println(renderSummary(trusted, dev))
		fmt.Print("Approve [o]nce / [p]ermanent / [b]lock device / [s]kip: ")
		response, err := reader.ReadString('\n')
		if err != nil {
			return "skip", err
		}
		switch strings.ToLower(strings.TrimSpace(response)) {
		case "o", "once":
			ok, err := confirmSensitiveApprovalCLI(reader, dev)
			if err != nil {
				return "skip", err
			}
			if !ok {
				continue
			}
			return "approve-once", nil
		case "p", "permanent":
			ok, err := confirmSensitiveApprovalCLI(reader, dev)
			if err != nil {
				return "skip", err
			}
			if !ok {
				continue
			}
			ok, err = confirmPermanentCLI(reader, displayName(dev))
			if err != nil {
				return "skip", err
			}
			if ok {
				return "approve-permanently", nil
			}
		case "b", "block", "n", "no":
			decision, err := confirmBlockCLI(reader, displayName(dev))
			if err != nil {
				return "skip", err
			}
			if decision != "" {
				return decision, nil
			}
		case "s", "skip", "", "c", "cancel":
			return "skip", nil
		}
	}
}

func promptGroupCLI(group []device) (string, []string, error) {
	reader := bufio.NewReader(os.Stdin)
	for {
		fmt.Println(renderDockSummary(group))
		fmt.Println("Selected by default:")
		for _, item := range group {
			fmt.Printf("  [x] [%s] %s\n", item.ID, displayName(item))
		}
		fmt.Print("Approve dock [o]nce / [p]ermanent / [b]lock device / [d]etails / [s]kip: ")
		mode, err := reader.ReadString('\n')
		if err != nil {
			return "skip", nil, err
		}
		ids := groupIDs(group)
		switch strings.ToLower(strings.TrimSpace(mode)) {
		case "o", "once":
			return "approve-once", ids, nil
		case "d", "details":
			fmt.Println(renderDockDetails(group))
			continue
		case "p", "permanent":
			ok, err := confirmPermanentCLI(reader, fmt.Sprintf("%d selected dock device(s)", len(ids)))
			if err != nil {
				return "skip", nil, err
			}
			if ok {
				return "approve-permanently", ids, nil
			}
		case "b", "block":
			decision, err := confirmBlockCLI(reader, fmt.Sprintf("%d dock device(s)", len(group)))
			if err != nil {
				return "skip", nil, err
			}
			if decision != "" {
				return decision, ids, nil
			}
		case "s", "skip", "", "c", "cancel":
			return "skip", nil, nil
		}
	}
}

func promptSingleYad(trusted map[string]string, dev device) (string, error) {
	tmp, err := os.CreateTemp("", "usbguard-review-*.txt")
	if err != nil {
		return "skip", err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(renderSummary(trusted, dev)); err != nil {
		tmp.Close()
		return "skip", err
	}
	if err := tmp.Close(); err != nil {
		return "skip", err
	}

	for {
		cmd := exec.Command("yad",
			"--title=USBGuard review: "+displayName(dev),
			"--width=980",
			"--height=760",
			"--center",
			"--text="+promptBanner(dev),
			"--text-align=left",
			"--text-info",
			"--filename="+tmp.Name(),
			"--button=Approve once:0",
			"--button=Approve permanently:2",
			"--button=Block device:3",
			"--button=Skip:1",
		)
		cmd.Env = os.Environ()
		output, err := cmd.CombinedOutput()
		switch exitCode(err) {
		case 0:
			ok, err := confirmSensitiveApprovalYad(dev)
			if err != nil {
				return "skip", err
			}
			if !ok {
				continue
			}
			return "approve-once", nil
		case 2:
			ok, err := confirmSensitiveApprovalYad(dev)
			if err != nil {
				return "skip", err
			}
			if !ok {
				continue
			}
			ok, err = confirmPermanentYad(displayName(dev))
			if err != nil {
				return "skip", err
			}
			if ok {
				return "approve-permanently", nil
			}
			continue
		case 3:
			decision, err := confirmBlockYad(displayName(dev))
			if err != nil {
				return "skip", err
			}
			if decision != "" {
				return decision, nil
			}
			continue
		case 1, 252:
			return "skip", nil
		default:
			return "skip", fmt.Errorf("yad prompt failed: %s", strings.TrimSpace(string(output)))
		}
	}
}

func promptGroupYad(group []device) (string, []string, error) {
	rows := make([]string, 0, len(group)*4)
	for _, item := range group {
		rows = append(rows, "TRUE", item.ID, displayName(item), riskLabelMarkup(riskLevel(item)))
	}

	for {
		args := []string{
			"--title=USBGuard review: Dock / USB-C device group",
			"--width=980",
			"--height=520",
			"--center",
			"--text=" + promptBannerGroup(group),
			"--text-align=left",
			"--list",
			"--checklist",
			"--use-markup",
			"--separator=|",
			"--print-column=2",
			"--column=Allow:CHK",
			"--column=ID:TEXT",
			"--column=Device:TEXT",
			"--column=Risk:TEXT",
			"--button=View details:4",
			"--button=Approve dock once:0",
			"--button=Approve dock permanently:2",
			"--button=Block device:3",
			"--button=Skip:1",
		}
		args = append(args, rows...)
		cmd := exec.Command("yad", args...)
		cmd.Env = os.Environ()
		output, err := cmd.CombinedOutput()
		selected := parseSelectedIDs(string(output))
		if len(selected) == 0 {
			selected = groupIDs(group)
		}
		switch exitCode(err) {
		case 0:
			return "approve-once", selected, nil
		case 2:
			ok, err := confirmPermanentYad(fmt.Sprintf("%d selected dock device(s)", len(selected)))
			if err != nil {
				return "skip", nil, err
			}
			if ok {
				return "approve-permanently", selected, nil
			}
			continue
		case 3:
			decision, err := confirmBlockYad(fmt.Sprintf("%d dock device(s)", len(group)))
			if err != nil {
				return "skip", nil, err
			}
			if decision != "" {
				return decision, selected, nil
			}
			continue
		case 4:
			if err := showDockDetailsYad(group); err != nil {
				return "skip", nil, err
			}
			continue
		case 1, 252:
			return "skip", nil, nil
		default:
			return "skip", nil, fmt.Errorf("yad group prompt failed: %s", strings.TrimSpace(string(output)))
		}
	}
}

func parseSelectedIDs(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, "|")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func confirmPermanentCLI(reader *bufio.Reader, name string) (bool, error) {
	fmt.Printf("Really allow %q permanently until rebuild? [y/N]: ", name)
	response, err := reader.ReadString('\n')
	if err != nil {
		return false, err
	}
	switch strings.ToLower(strings.TrimSpace(response)) {
	case "y", "yes":
		return true, nil
	default:
		return false, nil
	}
}

func confirmBlockCLI(reader *bufio.Reader, name string) (string, error) {
	fmt.Printf("Block %q [o]nce / [p]ermanently / [c]ancel: ", name)
	response, err := reader.ReadString('\n')
	if err != nil {
		return "", err
	}
	switch strings.ToLower(strings.TrimSpace(response)) {
	case "o", "once", "y", "yes":
		return "deny", nil
	case "p", "permanent":
		return "deny-permanently", nil
	default:
		return "", nil
	}
}

func confirmPermanentYad(name string) (bool, error) {
	cmd := exec.Command("yad",
		"--question",
		"--title=Confirm permanent approval",
		"--width=360",
		"--height=140",
		"--fixed",
		"--on-top",
		"--skip-taskbar",
		"--center",
		"--text=Allow \""+name+"\" permanently until the next rebuild?",
		"--button=No:1",
		"--button=Yes:0",
	)
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()
	switch exitCode(err) {
	case 0:
		return true, nil
	case 1, 252:
		return false, nil
	default:
		return false, fmt.Errorf("yad confirmation failed: %s", strings.TrimSpace(string(output)))
	}
}

func confirmBlockYad(name string) (string, error) {
	cmd := exec.Command("yad",
		"--title=Confirm block",
		"--width=380",
		"--height=150",
		"--fixed",
		"--on-top",
		"--skip-taskbar",
		"--center",
		"--text=How should \""+name+"\" stay blocked?",
		"--button=Cancel:1",
		"--button=Block once:0",
		"--button=Block permanently:2",
	)
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()
	switch exitCode(err) {
	case 0:
		return "deny", nil
	case 2:
		return "deny-permanently", nil
	case 1, 252:
		return "", nil
	default:
		return "", fmt.Errorf("yad block confirmation failed: %s", strings.TrimSpace(string(output)))
	}
}

func renderSummary(trusted map[string]string, dev device) string {
	lines := []string{
		"USB Device Review",
		"",
		"Name: " + displayName(dev),
		"Risk: " + riskLevel(dev),
		"State: " + firstNonEmpty(dev.Action, "<unknown>"),
		"USB ID: " + firstNonEmpty(dev.USBID, "<unknown>"),
		"Port: " + firstNonEmpty(dev.ViaPort, "<unknown>"),
		"Connect type: " + firstNonEmpty(dev.ConnectType, "<unknown>"),
		"Serial: " + firstNonEmpty(dev.Serial, "<none>"),
		"",
		"Why this might be risky:",
	}
	for _, note := range suspiciousNotes(dev) {
		lines = append(lines, "  - "+note)
	}
	lines = append(lines, "", "Interfaces:")
	if len(dev.Interfaces) == 0 {
		lines = append(lines, "  - <none reported>")
	} else {
		for _, item := range dev.Interfaces {
			lines = append(lines, "  - "+item)
		}
	}
	if label := trusted[dev.Rule]; label != "" {
		lines = append(lines, "", "Repo note: already present in whitelist.json as "+label+".")
	} else {
		lines = append(lines, "", "Repo note: this device is not present in whitelist.json.")
	}
	lines = append(lines, "", "Raw USBGuard rule:", dev.Rule)
	return strings.Join(lines, "\n")
}

func renderDockSummary(group []device) string {
	lines := []string{
		"Dock / USB-C Chain Review",
		"",
		fmt.Sprintf("This group contains %d related dock device(s).", len(group)),
		"Storage-class and HID devices are intentionally split out and reviewed separately.",
		"",
		"Members:",
	}
	for _, item := range group {
		lines = append(lines, fmt.Sprintf("  - [%s] %s (%s)", item.ID, displayName(item), riskLevel(item)))
	}
	lines = append(lines, "", "Use 'View details' to inspect ports, IDs, and interfaces before allowing the dock.")
	return strings.Join(lines, "\n")
}

func renderDockDetails(group []device) string {
	lines := []string{"Dock group details", ""}
	for _, item := range group {
		lines = append(lines,
			fmt.Sprintf("[%s] %s", item.ID, displayName(item)),
			"  Risk: "+riskLevel(item),
			"  USB ID: "+firstNonEmpty(item.USBID, "<unknown>"),
			"  Port: "+firstNonEmpty(item.ViaPort, "<unknown>"),
			"  Connect type: "+firstNonEmpty(item.ConnectType, "<unknown>"),
		)
		if len(item.Interfaces) == 0 {
			lines = append(lines, "  Interfaces: <none reported>", "")
			continue
		}
		lines = append(lines, "  Interfaces: "+strings.Join(item.Interfaces, ", "), "")
	}
	return strings.Join(lines, "\n")
}

func promptBanner(dev device) string {
	risk := riskLevel(dev)
	banner := []string{fmt.Sprintf("<span foreground=\"%s\" weight=\"bold\" size=\"x-large\">Risk: %s</span>", riskColor(risk), risk)}
	for _, note := range suspiciousNotes(dev) {
		banner = append(banner, fmt.Sprintf("<span foreground=\"%s\">Warning: %s</span>", riskColor(risk), escapeMarkup(note)))
	}
	banner = append(banner, fmt.Sprintf("<span weight=\"bold\">%s</span> <span foreground=\"#aaaaaa\">(%s)</span>", escapeMarkup(displayName(dev)), escapeMarkup(firstNonEmpty(dev.USBID, "<unknown>"))))
	return strings.Join(banner, "\n")
}

func promptBannerGroup(group []device) string {
	return fmt.Sprintf("<span foreground=\"#f6c177\" weight=\"bold\">Review the dock as one item. This group contains %d attached dock subdevice(s). Storage and HID devices are reviewed separately. Unticked entries stay blocked.</span>", len(group))
}

func riskLabelMarkup(risk string) string {
	switch risk {
	case "High":
		return "<span foreground=\"#ff6b6b\">danger</span>"
	case "Medium":
		return "<span foreground=\"#f6c177\">safe-ish</span>"
	default:
		return "<span foreground=\"#98c379\">safe</span>"
	}
}

func suspiciousNotes(dev device) []string {
	notes := []string{}
	name := strings.ToLower(strings.TrimSpace(dev.Name))
	if name == "" || strings.Contains(name, "unknown") || strings.Contains(name, "usb device") || strings.Contains(name, "simple hid") {
		notes = append(notes, "Name looks generic or underspecified.")
	}
	if strings.TrimSpace(dev.Serial) == "" {
		notes = append(notes, "No serial exposed by the device.")
	}
	if dev.ConnectType == "" || dev.ConnectType == "unknown" || dev.ConnectType == "hotplug" {
		notes = append(notes, "Connect type looks external or unspecified.")
	}
	if hasPrefix(dev, "03:") {
		notes = append(notes, "Device exposes HID-style interfaces and could inject input if approved.")
	}
	if has(dev, "03:01:01") {
		notes = append(notes, "Claims a keyboard interface, which is high risk if unexpected.")
	}
	if hasPrefix(dev, "08:") {
		notes = append(notes, "Exposes storage-related interfaces.")
	}
	if has(dev, "02:06:00") || hasPrefix(dev, "0a:") {
		notes = append(notes, "Exposes network-related interfaces.")
	}
	if looksLikeDock(dev) {
		notes = append(notes, "Looks like part of a dock or USB-C chain; blocking it can affect charging, displays, Ethernet, audio, or card readers.")
	}
	if len(notes) == 0 {
		notes = append(notes, "No obvious red flags from the quick heuristic summary.")
	}
	return notes
}

func riskLevel(dev device) string {
	switch {
	case has(dev, "03:01:01"):
		return "High"
	case hasPrefix(dev, "03:"), hasPrefix(dev, "08:"), has(dev, "02:06:00"), hasPrefix(dev, "0a:"):
		return "Medium"
	default:
		return "Low"
	}
}

func riskColor(risk string) string {
	switch strings.ToLower(risk) {
	case "high":
		return "#ff6b6b"
	case "medium":
		return "#f6c177"
	default:
		return "#98c379"
	}
}

func riskBadge(dev device) string {
	risk := riskLevel(dev)
	return fmt.Sprintf("%s(%s)", risk, riskColor(risk))
}

func needsSensitiveApproval(dev device) bool {
	if looksLikeDock(dev) || looksLikeDockChainMember(dev) {
		return false
	}
	return hasPrefix(dev, "08:") || has(dev, "02:06:00") || hasPrefix(dev, "0a:")
}

func sensitiveWarningText(dev device) string {
	parts := []string{}
	if hasPrefix(dev, "08:") {
		parts = append(parts, "storage")
	}
	if has(dev, "02:06:00") || hasPrefix(dev, "0a:") {
		parts = append(parts, "network or wireless")
	}
	if len(parts) == 0 {
		return ""
	}
	return fmt.Sprintf("%s exposes %s capabilities and does not look like a built-in dock component.", displayName(dev), strings.Join(parts, " + "))
}

func colorizeRiskLabel(risk string) string {
	switch strings.ToLower(risk) {
	case "high":
		return "\033[38;2;255;107;107mHigh\033[0m"
	case "medium":
		return "\033[38;2;246;193;119mMedium\033[0m"
	default:
		return "\033[38;2;152;195;121mLow\033[0m"
	}
}

func looksLikeDock(dev device) bool {
	text := strings.ToLower(dev.Name + " " + dev.USBID)
	explicitDockMarkers := []string{
		"dock",
		"docking",
		"billboard",
		"displaylink",
		"parade",
		"genesys",
		"ethernet",
		"lan",
		"card reader",
		"rtl8153",
		"rtl8156",
		"realtek",
		"asix",
		"ax88179",
		"lan78",
		"cdc ncm",
		"cdc ecm",
		"rndis",
		"usb 10/100/1000 lan",
	}
	obviousNonDockMarkers := []string{
		"bluetooth",
		"fingerprint",
		"webcam",
		"camera",
		"headset",
		"dongle",
		"receiver",
		"adapter",
		"extender",
	}
	if containsAny(text, obviousNonDockMarkers) && !containsAny(text, explicitDockMarkers) {
		return false
	}
	if containsAny(text, explicitDockMarkers) {
		return true
	}
	rich := 0
	if hasPrefix(dev, "09:") {
		rich++
	}
	if has(dev, "02:06:00") || hasPrefix(dev, "0a:") {
		rich++
	}
	if hasPrefix(dev, "08:") || hasPrefix(dev, "0e:") || hasPrefix(dev, "11:") {
		rich++
	}
	return rich >= 2
}

func hasHID(dev device) bool {
	return hasPrefix(dev, "03:")
}

func looksLikeDockChainMember(dev device) bool {
	if strings.Count(dev.ViaPort, ".") < 2 {
		return false
	}
	if looksLikeDock(dev) {
		return true
	}
	return has(dev, "02:06:00") || hasPrefix(dev, "0a:") || hasPrefix(dev, "09:") || hasPrefix(dev, "0e:") || hasPrefix(dev, "11:")
}

func dockGroupEligible(dev device) bool {
	if hasPrefix(dev, "08:") || hasHID(dev) {
		return false
	}
	return looksLikeDock(dev) || hasPrefix(dev, "09:") || hasPrefix(dev, "0e:") || has(dev, "02:06:00") || hasPrefix(dev, "0a:")
}

func dockGroup(c cfg, all []device, anchor device) []device {
	if c.DisableDockGrouping || !dockGroupEligible(anchor) {
		return []device{anchor}
	}
	token := rootPortToken(anchor)
	if token == "" {
		return []device{anchor}
	}
	group := []device{}
	for _, item := range all {
		if rootPortToken(item) != token || !dockGroupEligible(item) {
			continue
		}
		group = append(group, item)
	}
	if len(group) <= 1 {
		return []device{anchor}
	}
	sort.SliceStable(group, func(i, j int) bool {
		return group[i].ViaPort < group[j].ViaPort
	})
	return group
}

func rootPortToken(dev device) string {
	if !strings.Contains(dev.ViaPort, "-") {
		return ""
	}
	suffix := strings.SplitN(dev.ViaPort, "-", 2)[1]
	return strings.SplitN(suffix, ".", 2)[0]
}

func approve(c cfg, dev device, permanent bool) error {
	if permanent {
		// Save to local transient allowed list because NixOS rules are read-only
		_ = savePersistedRule(c.AllowedPath, displayName(dev), "allow "+dev.Rule, riskLevel(dev))
		// Attempt to append anyway (might work if daemon is configured for it)
		_, _ = run("usbguard", "append-rule", "allow "+dev.Rule)
	}
	_, err := run("usbguard", "allow-device", dev.ID)
	return err
}

func blockDevice(dev device) error {
	_, err := run("usbguard", "block-device", dev.ID)
	return err
}

func blockRuleFor(dev device) string {
	return "block " + dev.Rule
}

func persistBlock(c cfg, dev device, blacklist persistedRules) error {
	rule := blockRuleFor(dev)
	if _, ok := blacklistLabelForRule(blacklist, rule); !ok {
		if _, err := run("usbguard", "append-rule", rule); err != nil {
			return err
		}
	}
	if err := savePersistedRule(c.BlacklistPath, displayName(dev), rule, riskLevel(dev)); err != nil {
		return err
	}
	return blockDevice(dev)
}

func displayName(dev device) string {
	if strings.TrimSpace(dev.Name) != "" {
		return dev.Name
	}
	if strings.TrimSpace(dev.USBID) != "" {
		return dev.USBID
	}
	return "Unknown USB device"
}

func queueLabel(dev device) string {
	return firstNonEmpty(displayName(dev), dev.USBID, dev.ID)
}

func groupIDs(group []device) []string {
	ids := make([]string, 0, len(group))
	for _, item := range group {
		ids = append(ids, item.ID)
	}
	return ids
}

func deviceKey(dev device) string {
	sum := sha256.Sum256([]byte(strings.Join([]string{dev.Hash, dev.USBID, dev.Serial, dev.ViaPort}, "|")))
	return hex.EncodeToString(sum[:])
}

func markerState(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	parts := strings.Fields(string(data))
	if len(parts) == 0 {
		return ""
	}
	return parts[0]
}

func writeMarker(path, state string) error {
	return os.WriteFile(path, []byte(fmt.Sprintf("%s %d\n", state, time.Now().Unix())), 0o644)
}

func loadPersistedRules(path string) persistedRules {
	data, err := os.ReadFile(path)
	if err != nil {
		return persistedRules{}
	}
	var rules persistedRules
	if err := json.Unmarshal(data, &rules); err != nil {
		return persistedRules{}
	}
	return rules
}

func savePersistedRules(path string, rules persistedRules) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(rules, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

func savePersistedRule(path, label, rule, risk string) error {
	rules := loadPersistedRules(path)
	updated := false
	for idx, item := range rules.Devices {
		if item.Rule == rule {
			if item.UUID == "" {
				rules.Devices[idx].UUID = persistentRuleUUID(item.Rule)
				updated = true
			}
			if strings.TrimSpace(item.Risk) == "" && strings.TrimSpace(risk) != "" {
				rules.Devices[idx].Risk = risk
				updated = true
			}
			if strings.TrimSpace(item.Label) == "" && strings.TrimSpace(label) != "" {
				rules.Devices[idx].Label = label
				updated = true
			}
			if updated {
				return savePersistedRules(path, rules)
			}
			return nil
		}
	}
	rules.Devices = append(rules.Devices, struct {
		UUID  string `json:"uuid,omitempty"`
		Label string `json:"label"`
		Risk  string `json:"risk,omitempty"`
		Rule  string `json:"rule"`
	}{
		UUID:  persistentRuleUUID(rule),
		Label: label,
		Risk:  risk,
		Rule:  rule,
	})
	return savePersistedRules(path, rules)
}

func blacklistLabelFor(rules persistedRules, dev device) (string, bool) {
	return blacklistLabelForRule(rules, blockRuleFor(dev))
}

func blacklistLabelForRule(rules persistedRules, rule string) (string, bool) {
	for _, item := range rules.Devices {
		if item.Rule == rule {
			return item.Label, true
		}
	}
	return "", false
}

func removePersistedRule(path, rule string) error {
	rules := loadPersistedRules(path)
	filtered := persistedRules{}
	for _, item := range rules.Devices {
		if item.Rule == rule {
			continue
		}
		filtered.Devices = append(filtered.Devices, item)
	}
	return savePersistedRules(path, filtered)
}

func releasePersistentBlock(c cfg, dev device) error {
	rule := blockRuleFor(dev)
	if err := removeMatchingRuntimeRule(rule); err != nil {
		return err
	}
	return removePersistedRule(c.BlacklistPath, rule)
}

func removeMatchingRuntimeRule(rule string) error {
	out, err := run("usbguard", "list-rules")
	if err != nil {
		return err
	}
	scanner := bufio.NewScanner(strings.NewReader(out))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		idx := strings.Index(line, ":")
		if idx <= 0 {
			continue
		}
		id := strings.TrimSpace(line[:idx])
		current := strings.TrimSpace(line[idx+1:])
		if current != rule {
			continue
		}
		if _, err := run("usbguard", "remove-rule", id); err != nil {
			return err
		}
	}
	return scanner.Err()
}

func persistentRuleUUID(rule string) string {
	sum := sha256.Sum256([]byte(rule))
	return hex.EncodeToString(sum[:8])
}

func shouldAutoQuarantineStorage(dev device) bool {
	return hasPrefix(dev, "08:")
}

func quarantineStorageDevice(c cfg, dev device, blacklist persistedRules) (string, error) {
	rule := blockRuleFor(dev)
	if err := persistBlock(c, dev, blacklist); err != nil {
		return "", err
	}
	return persistentRuleUUID(rule), nil
}

func persistedRuleDisplayName(label string) string {
	label = strings.TrimSpace(label)
	if label == "" || strings.EqualFold(label, "unknown usb device") {
		return "Unknown USB device [name missing]"
	}
	return label
}

func persistedRuleDisplayNameMarkup(label string) string {
	clean := persistedRuleDisplayName(label)
	if strings.Contains(clean, "[name missing]") {
		return escapeMarkup(clean[:len(clean)-len(" [name missing]")]) + " <span foreground=\"#ff6b6b\">[name missing]</span>"
	}
	return escapeMarkup(clean)
}

func persistedRuleRisk(item struct {
	UUID  string `json:"uuid,omitempty"`
	Label string `json:"label"`
	Risk  string `json:"risk,omitempty"`
	Rule  string `json:"rule"`
}) string {
	if strings.TrimSpace(item.Risk) != "" {
		return item.Risk
	}
	switch {
	case strings.Contains(item.Rule, "03:01:01"):
		return "High"
	case strings.Contains(item.Rule, "03:"), strings.Contains(item.Rule, "08:"), strings.Contains(item.Rule, "02:06:00"), strings.Contains(item.Rule, "0a:"):
		return "Medium"
	default:
		return "Low"
	}
}

func persistedRuleRiskMarkup(item struct {
	UUID  string `json:"uuid,omitempty"`
	Label string `json:"label"`
	Risk  string `json:"risk,omitempty"`
	Rule  string `json:"rule"`
}) string {
	return riskLabelMarkup(persistedRuleRisk(item))
}

func releasePersistentBlockByUUID(c cfg, uuid string) (bool, error) {
	rules := loadPersistedRules(c.BlacklistPath)
	filtered := persistedRules{}
	releasedRule := ""
	for _, item := range rules.Devices {
		itemUUID := item.UUID
		if itemUUID == "" {
			itemUUID = persistentRuleUUID(item.Rule)
		}
		if itemUUID == uuid {
			releasedRule = item.Rule
			continue
		}
		filtered.Devices = append(filtered.Devices, item)
	}
	if releasedRule == "" {
		return false, nil
	}
	if err := removeMatchingRuntimeRule(releasedRule); err != nil {
		return false, err
	}
	if err := savePersistedRules(c.BlacklistPath, filtered); err != nil {
		return false, err
	}
	if devices, err := blockedDevices(c); err == nil {
		seenDir := filepath.Join(c.StateDir, "seen")
		for _, dev := range devices {
			if blockRuleFor(dev) != releasedRule {
				continue
			}
			_ = os.Remove(filepath.Join(seenDir, deviceKey(dev)))
		}
	}
	return true, nil
}

func promptReleasePersistentBlocksCLI(c cfg) error {
	rules := loadPersistedRules(c.BlacklistPath)
	if len(rules.Devices) == 0 {
		fmt.Println("No persistent blocked USB devices are recorded.")
		return nil
	}
	fmt.Println("Persistent blocked USB devices:")
	for _, item := range rules.Devices {
		uuid := item.UUID
		if uuid == "" {
			uuid = persistentRuleUUID(item.Rule)
		}
		fmt.Printf("  [%s] %s (%s)\n", uuid, persistedRuleDisplayName(item.Label), strings.ToLower(persistedRuleRisk(item)))
	}
	fmt.Print("Enter UUIDs to release, separated by spaces, or leave blank to cancel: ")
	reader := bufio.NewReader(os.Stdin)
	line, err := reader.ReadString('\n')
	if err != nil {
		return err
	}
	selected := strings.Fields(strings.TrimSpace(line))
	if len(selected) == 0 {
		return nil
	}
	for _, uuid := range selected {
		if _, err := releasePersistentBlockByUUID(c, uuid); err != nil {
			return err
		}
		fmt.Printf("Released persistent block %s back into the review queue.\n", uuid)
	}
	return nil
}

func promptReleasePersistentBlocksYad(c cfg) error {
	rules := loadPersistedRules(c.BlacklistPath)
	if len(rules.Devices) == 0 {
		cmd := exec.Command("yad",
			"--info",
			"--title=USBGuard persistent block list",
			"--width=520",
			"--height=140",
			"--center",
			"--text=No persistent blocked USB devices are recorded.",
			"--button=Close:0",
		)
		cmd.Env = os.Environ()
		_, _ = cmd.CombinedOutput()
		return nil
	}

	rows := []string{}
	for _, item := range rules.Devices {
		uuid := item.UUID
		if uuid == "" {
			uuid = persistentRuleUUID(item.Rule)
		}
		rows = append(rows, "FALSE", uuid, persistedRuleDisplayNameMarkup(item.Label), persistedRuleRiskMarkup(item))
	}

	cmdArgs := []string{
		"--title=USBGuard persistent block list",
		"--width=980",
		"--height=520",
		"--center",
		"--text=<span foreground=\"#f6c177\" weight=\"bold\">Select persistent blocked devices to release back into the approval queue. Unticked entries stay blocked.</span>\n<span foreground=\"#98c379\">safe</span> <span foreground=\"#f6c177\">safe-ish</span> <span foreground=\"#ff6b6b\">danger</span>",
		"--text-align=left",
		"--list",
		"--checklist",
		"--use-markup",
		"--separator=|",
		"--print-column=2",
		"--column=Release:CHK",
		"--column=UUID:TEXT",
		"--column=Device:TEXT",
		"--column=Risk:TEXT",
		"--button=Release selected:0",
		"--button=Cancel:1",
	}
	cmdArgs = append(cmdArgs, rows...)
	cmd := exec.Command("yad", cmdArgs...)
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()
	switch exitCode(err) {
	case 0:
		selected := parseSelectedIDs(string(output))
		if len(selected) == 0 {
			return nil
		}
		for _, uuid := range selected {
			if _, err := releasePersistentBlockByUUID(c, uuid); err != nil {
				return err
			}
		}
		return nil
	case 1, 252:
		return nil
	default:
		return fmt.Errorf("yad release prompt failed: %s", strings.TrimSpace(string(output)))
	}
}

func confirmSensitiveApprovalCLI(reader *bufio.Reader, dev device) (bool, error) {
	if !needsSensitiveApproval(dev) {
		return true, nil
	}
	fmt.Printf("%s Approve anyway? [y/N]: ", sensitiveWarningText(dev))
	response, err := reader.ReadString('\n')
	if err != nil {
		return false, err
	}
	switch strings.ToLower(strings.TrimSpace(response)) {
	case "y", "yes":
		return true, nil
	default:
		return false, nil
	}
}

func confirmSensitiveApprovalYad(dev device) (bool, error) {
	if !needsSensitiveApproval(dev) {
		return true, nil
	}
	cmd := exec.Command("yad",
		"--question",
		"--title=Sensitive USB approval",
		"--width=430",
		"--height=150",
		"--fixed",
		"--on-top",
		"--skip-taskbar",
		"--center",
		"--text="+escapeMarkup(sensitiveWarningText(dev)),
		"--button=Cancel:1",
		"--button=Approve anyway:0",
	)
	cmd.Env = os.Environ()
	output, err := cmd.CombinedOutput()
	switch exitCode(err) {
	case 0:
		return true, nil
	case 1, 252:
		return false, nil
	default:
		return false, fmt.Errorf("yad sensitive approval failed: %s", strings.TrimSpace(string(output)))
	}
}

func showDockDetailsYad(group []device) error {
	tmp, err := os.CreateTemp("", "usbguard-dock-details-*.txt")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(renderDockDetails(group)); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	cmd := exec.Command("yad",
		"--title=Dock device details",
		"--width=860",
		"--height=520",
		"--center",
		"--text-info",
		"--filename="+tmp.Name(),
		"--button=Back:0",
	)
	cmd.Env = os.Environ()
	if output, err := cmd.CombinedOutput(); err != nil && exitCode(err) != 0 {
		return fmt.Errorf("yad dock details failed: %s", strings.TrimSpace(string(output)))
	}
	return nil
}

func cleanupSeenDir(dir string, active map[string]bool) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, entry := range entries {
		if active[entry.Name()] {
			continue
		}
		if err := os.Remove(filepath.Join(dir, entry.Name())); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return nil
}

func notify(title, body string) {
	if strings.TrimSpace(os.Getenv("DISPLAY")) == "" && strings.TrimSpace(os.Getenv("WAYLAND_DISPLAY")) == "" {
		return
	}
	_ = exec.Command("notify-send", title, body).Run()
}

func canPromptGraphically(c cfg) bool {
	if !c.Popups {
		return false
	}
	if strings.TrimSpace(os.Getenv("DISPLAY")) == "" && strings.TrimSpace(os.Getenv("WAYLAND_DISPLAY")) == "" {
		return false
	}
	_, err := exec.LookPath("yad")
	return err == nil
}

func approvalPrefix(decision string) string {
	if decision == "approve-permanently" {
		return "Approved permanently"
	}
	if decision == "approve-once" {
		return "Approved once"
	}
	return "Left blocked"
}

func summarizeNames(names []string) string {
	if len(names) == 0 {
		return ""
	}
	if len(names) == 1 {
		return names[0]
	}
	if len(names) == 2 {
		return names[0] + ", " + names[1]
	}
	return fmt.Sprintf("%s, %s, +%d more", names[0], names[1], len(names)-2)
}

func sliceToSet(values []string) map[string]bool {
	result := map[string]bool{}
	for _, value := range values {
		result[value] = true
	}
	return result
}

func escapeMarkup(s string) string {
	replacer := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;")
	return replacer.Replace(s)
}

func has(dev device, exact string) bool {
	for _, item := range dev.Interfaces {
		if item == exact {
			return true
		}
	}
	return false
}

func hasPrefix(dev device, prefix string) bool {
	for _, item := range dev.Interfaces {
		if strings.HasPrefix(item, prefix) {
			return true
		}
	}
	return false
}

func containsAny(text string, markers []string) bool {
	for _, marker := range markers {
		if strings.Contains(text, marker) {
			return true
		}
	}
	return false
}

func run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Env = os.Environ()
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		if stderr.Len() > 0 {
			return stdout.String(), fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
		}
		return stdout.String(), err
	}
	return stdout.String(), nil
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}

func envBool(name string, fallback bool) bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(name)))
	switch value {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func envInt(name string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envSeconds(name string, fallback float64) time.Duration {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return time.Duration(fallback * float64(time.Second))
	}
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return time.Duration(fallback * float64(time.Second))
	}
	return time.Duration(parsed * float64(time.Second))
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
