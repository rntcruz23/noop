package com.noop.analytics

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** Pure selected-window projection shared by trend-card callers. */
object TrendWindow {
    data class Point(val day: String, val value: Double)

    data class Result(
        val points: List<Point>,
        val startDay: String?,
        val endDay: String,
        val observed: Int,
        val expected: Int,
        val hasOlderHistory: Boolean,
    )

    fun project(
        rows: List<Pair<String, Double?>>,
        todayKey: String,
        dayCount: Int?,
    ): Result {
        val today = parse(todayKey)
            ?: return Result(emptyList(), null, todayKey, 0, 0, false)
        val resolved = linkedMapOf<String, Double>()
        rows.forEach { (day, value) ->
            val date = parse(day)
            if (date != null && !date.isAfter(today) && value != null && value.isFinite()) {
                resolved[day] = value
            }
        }
        val sorted = resolved.map { Point(it.key, it.value) }.sortedBy { it.day }
        val start = when {
            dayCount == null -> sorted.firstOrNull()?.day?.let(::parse)
            dayCount <= 0 -> null
            else -> today.minusDays((dayCount - 1).toLong())
        }
        if (start == null) {
            return Result(emptyList(), null, todayKey, 0, 0, sorted.isNotEmpty())
        }
        val startKey = start.toString()
        val points = sorted.filter { it.day >= startKey && it.day <= todayKey }
        val expected = ChronoUnit.DAYS.between(start, today).toInt() + 1
        return Result(
            points = points,
            startDay = startKey,
            endDay = todayKey,
            observed = points.size,
            expected = expected.coerceAtLeast(0),
            hasOlderHistory = sorted.any { it.day < startKey },
        )
    }

    /** Finite observations in the equal calendar interval immediately before the selected window. */
    fun previousPoints(
        rows: List<Pair<String, Double?>>,
        todayKey: String,
        dayCount: Int?,
    ): List<Point> {
        if (dayCount == null || dayCount <= 0) return emptyList()
        val today = parse(todayKey) ?: return emptyList()
        return project(rows, today.minusDays(dayCount.toLong()).toString(), dayCount).points
    }

    private fun parse(key: String): LocalDate? = runCatching { LocalDate.parse(key) }
        .getOrNull()
        ?.takeIf { it.toString() == key }
}
