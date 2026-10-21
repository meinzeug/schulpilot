"""Read-only portions toward minimum goals, with explicit optional next steps."""

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo


def period_starts(day, timezone):
    zone = ZoneInfo(timezone)
    monday = day - timedelta(days=day.weekday())
    return (
        int(datetime.combine(day, datetime.min.time(), zone).timestamp()),
        int(datetime.combine(monday, datetime.min.time(), zone).timestamp()),
    )


def completed_portions(units, prefs, start, week):
    """Finished portions use their estimate; this is never reported as active time.

    Fast answers must not refill the day with an unlimited succession of stages.
    Long prepared units count at most one daily/session portion on completion.
    """
    daily = weekly = 0
    for unit in units:
        if not unit.completed or unit.completed < week:
            continue
        minutes = min(
            unit.estimated_minutes or min(8, prefs.session_minutes), prefs.session_minutes, prefs.daily_minutes
        )
        weekly += minutes
        if unit.completed >= start:
            daily += minutes
    return daily, weekly


def reason(item):
    if item.get("mandatory"):
        return "parent_goal"
    if item.get("status") in ("active", "paused"):
        return "continue"
    if item["kind"] in ("review", "vocabulary"):
        return "review"
    return "material"


def voluntary_steps(candidates, today):
    """Offer manual choices, retaining source order and actual release dates.

    Weekdays, rest preferences and minutes shape the suggested plan only.
    This list never creates an exercise or changes a binding parent assignment.
    """
    first_in_chain = {}
    for item in candidates:
        if item.get("_chain"):
            chain = item["_chain"]
            first_in_chain[chain] = min(first_in_chain.get(chain, item["_sequence"]), item["_sequence"])
    result = []
    for item in candidates:
        if any(item.get(key) and item[key] > today.isoformat() for key in ("scheduled_for", "not_before")):
            continue
        if item.get("_chain") and item["_sequence"] > first_in_chain[item["_chain"]]:
            continue
        # A parent assignment already practised today stays visible as a goal;
        # its completed round is not silently replaced with another AI request.
        if item["status"] == "practiced_today":
            continue
        result.append({k: v for k, v in item.items() if not k.startswith("_")} | {"reason": reason(item)})
    return result


def distribute(candidates, prefs, today, *, daily_seconds=0, weekly_seconds=0, completed_chains=None):
    """Project modest portions; a weekly minimum never caps another day's plan.

    Future dates are suggestions, not persisted deadlines or generated exercises.
    A prepared unit can be spread across days; an ungenerated stage stays atomic.
    """
    pending = [dict(item, reason=reason(item)) for item in candidates]
    week = []
    assigned = {}
    finished = {}
    weighted_subjects = {}
    weighted_plan = any(item.get("_grade_priority", 0) for item in pending)
    for offset in range(7):
        day = today + timedelta(days=offset)
        free = day.weekday() not in prefs.weekdays
        paused = bool(prefs.pause_until and day <= prefs.pause_until)
        daily_left = max(0, prefs.daily_minutes - ((daily_seconds + 59) // 60 if offset == 0 else 0))
        capacity = 0 if free or paused else daily_left
        remaining, items, subjects, lanes, chains_today = capacity, [], {}, {}, {}
        if offset == 0:
            chains_today.update(completed_chains or {})
        while remaining:
            first_in_chain = {}
            for candidate in pending:
                if candidate.get("_chain"):
                    chain = candidate["_chain"]
                    first_in_chain[chain] = min(
                        first_in_chain.get(chain, candidate["_sequence"]), candidate["_sequence"]
                    )
            eligible = []
            for item in pending:
                if item.get("scheduled_for") and item["scheduled_for"] > day.isoformat():
                    continue
                if item.get("not_before") and item["not_before"] > day.isoformat():
                    continue
                if item["status"] == "practiced_today" and offset == 0:
                    continue
                if prefs.subject_days.get(item["subject"]) and day.weekday() not in prefs.subject_days[item["subject"]]:
                    continue
                # A later stage may follow its predecessor, never overtake it.
                if item.get("_chain") and first_in_chain[item["_chain"]] < item["_sequence"]:
                    continue
                if item.get("_chain") and chains_today.get(item["_chain"], 0) >= 3:
                    continue
                duration = item["estimated_minutes"]
                if item["kind"] == "unit":
                    duration = min(duration, prefs.session_minutes, remaining)
                if duration <= remaining:
                    eligible.append((item, duration))
            if not eligible:
                break

            def priority(pair):
                item, _ = pair
                recent = bool(item.get("source_date") and item["source_date"] >= (day - timedelta(days=1)).isoformat())
                # Parent dates stay binding; afterwards alternate subjects and mix
                # due retrieval practice, unfinished work and older source days.
                return (
                    not item.get("mandatory", False),
                    item.get("due") or "9999" if item.get("mandatory") else "9999",
                    (weighted_subjects if weighted_plan else subjects).get(item["subject"], 0) / (1 + item.get("_grade_priority", 0)),
                    -item.get("_grade_priority", 0),
                    {"continue": 0, "review": 1, "parent_goal": 0, "material": 2}[item["reason"]],
                    item.get("_ai_rank", 999),
                    lanes.get(recent, 0),
                    not recent,
                    item["subject"] not in prefs.focus_subjects,
                    item["topic"] not in prefs.repeat_topics,
                    item.get("_last_practiced") or "0000",
                    -date.fromisoformat(item["source_date"]).toordinal()
                    if recent
                    else date.fromisoformat(item.get("source_date") or "9999-12-31").toordinal(),
                    item.get("due") or "9999",
                    item.get("_sequence", 0),
                    item["id"],
                )

            item, duration = min(eligible, key=priority)
            key = (item["kind"], item["id"], item.get("block_id"))
            assigned.setdefault(key, day.isoformat())
            public = {k: v for k, v in item.items() if not k.startswith("_")}
            public.update(planned_for=day.isoformat(), estimated_minutes=duration)
            items.append(public)
            subjects[item["subject"]] = subjects.get(item["subject"], 0) + duration
            weighted_subjects[item["subject"]] = weighted_subjects.get(item["subject"], 0) + duration
            recent = bool(item.get("source_date") and item["source_date"] >= (day - timedelta(days=1)).isoformat())
            if item["reason"] == "material":
                lanes[recent] = lanes.get(recent, 0) + 1
            if item.get("_chain"):
                chains_today[item["_chain"]] = chains_today.get(item["_chain"], 0) + 1
                for other in pending:
                    if other.get("_chain") == item["_chain"]:
                        other["_last_practiced"] = day.isoformat()
            remaining -= duration
            if duration < item["estimated_minutes"]:
                item["estimated_minutes"] -= duration
                # A portion can continue tomorrow, without appearing twice today.
                item["not_before"] = (day + timedelta(days=1)).isoformat()
            else:
                finished[key] = day.isoformat()
                pending.remove(item)
        week.append(
            {
                "date": day.isoformat(),
                "available_minutes": capacity,
                "planned_minutes": capacity - remaining,
                "free_day": free,
                "paused": paused,
                "items": items,
            }
        )
    today_keys = {(x["kind"], x["id"], x.get("block_id")) for x in week[0]["items"]}
    later = []
    conflicts = []
    for item in candidates:
        key = (item["kind"], item["id"], item.get("block_id"))
        when = assigned.get(key)
        if (
            item.get("mandatory")
            and item.get("due")
            and item["due"] <= week[-1]["date"]
            and (not finished.get(key) or finished[key] > item["due"])
        ):
            conflicts.append({"id": item["id"], "topic": item["topic"], "due": item["due"], "planned_for": when})
        if key not in today_keys:
            later.append({k: v for k, v in item.items() if not k.startswith("_")} | {"planned_for": when})
    return {
        "today": week[0]["items"],
        "later": later,
        "week": week,
        "planned_minutes": week[0]["planned_minutes"],
        "backlog_steps": len(candidates),
        "beyond_week_steps": len(pending),
        "conflicts": conflicts,
    }
