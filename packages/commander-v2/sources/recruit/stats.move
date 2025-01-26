// Copyright (c) Sui Potatoes
// SPDX-License-Identifier: MIT

/// Universal stats for Recruits and their equipment, and for `Unit`s.
///
/// Stats are built in a way that allows easy modification, negation and
/// addition. Recruit stats are distributed in their equipment, and during the
/// conversion to `Unit` (pre-battle), the stats are combined into a single
/// `Stats` value.
module commander::stats;

use bit_field::bit_field as bf;
use std::{macros::num_min, string::String};
use sui::bcs::{Self, BCS};

/// Capped at 7 bits. Max value for signed 8-bit integers.
const SIGN_VALUE: u8 = 0x80;
/// Number of bitmap encoded parameters.
const NUM_PARAMS: u8 = 15;

/// Error code for not implemented functions.
const ENotImplemented: u64 = 264;

/// The `Stats` struct is a single uint value that stores all the stats of
/// a `Recruit` in a single value. It uses bit manipulation to store the values
/// at the right positions.
///
/// 16 values in a single u128 (in order):
/// - mobility
/// - aim
/// - health
/// - armor
/// - dodge
/// - defense (natural + cover bonus)
/// - damage
/// - spread
/// - plus_one (extra damage)
/// - crit_chance
/// - is_dodgeable
/// - area_size
/// - env_damage
/// - range
/// - ammo
/// - xxx (one u8 value is unused)
public struct Stats(u128) has copy, drop, store;

/// Create a new `BitStats` struct with the given values.
public fun new(mobility: u8, aim: u8, health: u8, armor: u8, dodge: u8): Stats {
    Stats(bf::pack_u8!(vector[mobility, aim, health, armor, dodge]))
}

/// Create a new `Stats` struct with the given unchecked value.
public fun new_unchecked(v: u128): Stats { Stats(v) }

/// Negates the modifier values. Creates a new `Modifier` which, when applied to
/// the `WeaponStats`, will negate the effects of the original modifier.
public fun negate(stats: &Stats): Stats {
    let stats = stats.0;
    let sign = SIGN_VALUE;
    let negated = bf::unpack_u8!(stats, NUM_PARAMS).map!(|value| {
        if (value > sign) value - sign else value + sign
    });

    Stats(bf::pack_u8!(negated))
}

/// Default stats for a Recruit.
public fun default(): Stats { new(7, 65, 10, 0, 0) }

/// Default stats for a Weapon.
public fun default_weapon(): Stats {
    // reverse:
    // 6-14 -> damage, spread, plus_one, crit_chance, is_dodgeable, area_size, env_damage, range, ammo
    Stats(0x03_04_00_01_01_00_00_02_04 << (6 * 8))
}

/// Default stats for an Armor.
public fun default_armor(): Stats { new(0, 0, 0, 0, 0) }

/// Get the `mobility` stat.
public fun mobility(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 0) }

/// Get the `aim` stat.
public fun aim(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 1) }

/// Get the `health` stat.
public fun health(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 2) }

/// Get the `armor` stat.
public fun armor(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 3) }

/// Get the `dodge` stat.
public fun dodge(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 4) }

/// Get the `defense` stat.
public fun defense(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 5) }

// === Weapon Stats ===

/// Get the `damage` stat.
public fun damage(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 6) }

/// Get the `spread` stat.
public fun spread(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 7) }

/// Get the `plus_one` stat.
public fun plus_one(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 8) }

/// Get the `crit_chance` stat.
public fun crit_chance(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 9) }

/// Get the `is_dodgeable` stat.
public fun is_dodgeable(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 10) }

/// Get the `area_size` stat.
public fun area_size(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 11) }

/// Get the `env_damage` stat.
public fun env_damage(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 12) }

/// Get the `range` stat.
public fun range(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 13) }

/// Get the `ammo` stat.
public fun ammo(stats: &Stats): u8 { bf::read_u8_at_offset!(stats.0, 14) }

/// Get the inner `u128` value of the `Stats`. Can be used for performance
/// optimizations and macros.
public fun inner(stats: &Stats): u128 { stats.0 }

// === Modifier ===

/// Apply the modifier to the stats and return the modified value. Each value in
/// the `Modifier` can be positive or negative (the first sign bit is used), and
/// the value (0-127) is added or subtracted from the base stats.
///
/// The result can never overflow the base stats, and the values are capped at
/// the maximum values for each stat.
public fun add(stats: &Stats, modifier: &Stats): Stats {
    let stats = stats.0;
    let modifier = modifier.0;
    let sign = SIGN_VALUE;

    let mut stat_values = bf::unpack_u8!(stats, NUM_PARAMS);
    let modifier_values = bf::unpack_u8!(modifier, NUM_PARAMS);

    // version is not modified, the rest of the values are modified
    // based on the signed values of the modifier
    (NUM_PARAMS as u64).do!(|i| {
        let modifier = modifier_values[i];
        let value = stat_values[i];

        // skip 0 and -0 values
        if (modifier == 0 || modifier == sign) return;
        let new_value = if (modifier > sign) {
            value - num_min!(modifier - sign, value)
        } else {
            // cannot overflow (127 is the max for modifier, below we cap values)
            value + modifier
        };

        *&mut stat_values[i] = num_min!(new_value, SIGN_VALUE - 1);
    });

    Stats(bf::pack_u8!(stat_values))
}

// === Convenience and compatibility ===

/// Print the `Stats` as a string.
public fun to_string(_stats: &Stats): String {
    abort ENotImplemented
}

/// Deserialize bytes into a `Rank`.
public fun from_bytes(bytes: vector<u8>): Stats {
    from_bcs(&mut bcs::new(bytes))
}

/// Helper method to allow nested deserialization of `Rank`.
public(package) fun from_bcs(bcs: &mut BCS): Stats {
    Stats(bcs.peel_u128())
}

#[test]
fun test_stats() {
    use std::unit_test::assert_eq;

    let stats = Self::new(
        7, // mobility
        50, // aim
        10, // health
        0, // armor
        0, // dodge
    );

    assert_eq!(stats.mobility(), 7);
    assert_eq!(stats.aim(), 50);
    assert_eq!(stats.health(), 10);
    assert_eq!(stats.armor(), 0);
    assert_eq!(stats.dodge(), 0);
}

#[test]
fun test_defaults() {
    use std::unit_test::assert_eq;

    let stats = Self::default();

    assert_eq!(stats.mobility(), 7);
    assert_eq!(stats.aim(), 65);
    assert_eq!(stats.health(), 10);
    assert_eq!(stats.armor(), 0);
    assert_eq!(stats.dodge(), 0);
    assert_eq!(stats.defense(), 0);

    assert_eq!(stats.damage(), 0);
    assert_eq!(stats.spread(), 0);
    assert_eq!(stats.plus_one(), 0);
    assert_eq!(stats.crit_chance(), 0);
    assert_eq!(stats.is_dodgeable(), 0);
    assert_eq!(stats.area_size(), 0);
    assert_eq!(stats.env_damage(), 0);
    assert_eq!(stats.range(), 0);
    assert_eq!(stats.ammo(), 0);

    let weapon_stats = Self::default_weapon();

    assert_eq!(weapon_stats.damage(), 4);
    assert_eq!(weapon_stats.spread(), 2);
    assert_eq!(weapon_stats.plus_one(), 0);
    assert_eq!(weapon_stats.crit_chance(), 0);
    assert_eq!(weapon_stats.is_dodgeable(), 1);
    assert_eq!(weapon_stats.area_size(), 1);
    assert_eq!(weapon_stats.env_damage(), 0);
    assert_eq!(weapon_stats.range(), 4);
    assert_eq!(weapon_stats.ammo(), 3);

    assert_eq!(weapon_stats.mobility(), 0);
    assert_eq!(weapon_stats.aim(), 0);
    assert_eq!(weapon_stats.health(), 0);
    assert_eq!(weapon_stats.armor(), 0);
    assert_eq!(weapon_stats.dodge(), 0);
    assert_eq!(weapon_stats.defense(), 0);
}

#[test]
fun test_with_modifier() {
    use std::unit_test::assert_eq;

    let stats = Self::new(7, 50, 10, 0, 0);
    let modifier = Self::new(128 + 2, 30, 0, 0, 0); // hyperfocus modifier: -2 mobility, +30 aim
    let modified = stats.add(&modifier); // apply the modifier and check the new stats

    assert_eq!(modified.mobility(), 5);
    assert_eq!(modified.aim(), 80);
    assert_eq!(modified.health(), 10);
    assert_eq!(modified.armor(), 0);
    assert_eq!(modified.dodge(), 0);

    // test negation
    assert_eq!(modified.add(&modifier.negate()), stats);

    // test overflow (max value) and underflow (arithmetic error) protection
    let modifier = Self::new(127, 0, 0, 255, 255);
    let modified = modified.add(&modifier);

    assert_eq!(modified.mobility(), SIGN_VALUE - 1); // overflow -> capped
    assert_eq!(modified.armor(), 0); // underflow -> 0
    assert_eq!(modified.dodge(), 0); // underflow -> 0
}
