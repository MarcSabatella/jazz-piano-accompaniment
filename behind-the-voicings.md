# Behind the Voicings: How Jazz Piano Accompaniment Works

A guide to the musical principles and voice-leading decisions behind the **Jazz Piano Accompaniment** plugin for MuseScore—written for pianists, arrangers, and curious tinkerers who want to know *why* the accompaniment lands on the notes it does.

Rather than dumping block chords or generic comping patterns onto a lead sheet, the plugin reads the melody, key signature, chord symbols, and phrase structure together and makes voicing decisions measure by measure.

---

## 1. Left Hand: Shells, Register, and Tenths

In two-hand piano accompaniment, the left hand lays down the harmonic anchor without crowding the middle register or getting in the way of the melody.

* **Bass register & tenor floor:** The bass generally stays in a comfortable low-to-mid range (`F2` to `F#3`), while the left-hand tenor voice stays at or above `C#3` so low thirds don't sound thick or muddy.
* **Tenths when the bass runs high:** If placing the bass in a standard octave would push it up to `G3` or higher, the plugin drops the bass an octave and opens up to a **10th** (such as `G2–B3` or `Bb2–D4`), provided the melody leaves enough room above it.
* **Complementing the melody:** When the melody prominently features the 3rd in the first half of a chord window, the left-hand tenor leans toward the 7th (and vice versa) to keep spacing open and avoid redundant doubling. If the 3rd or 7th doesn't appear in the melody until late in the bar (beat 3 or 4), the accompaniment steps in to establish it earlier.
* **Slash chords & inversions:**
  * *1st inversion (3rd in bass):* Pairs with the root or 5th in the left hand and places the 7th, 5th, or (when the RH would otherwise be empty) the 9th in the right hand.
  * *2nd or 3rd inversion (5th or 7th in bass):* Pairs with the 3rd in the left hand and voices the root (along with available guide or extension tones) in the right hand.

---

## 2. Right Hand: Guide Tones, Color Tones, and Melody Clearance

The right hand adds harmonic color and inner-voice support while staying clear of the melody.

* **Staying out of the melody's way:** Right-hand notes are kept below the lowest melody note of the chord's first half—with an exception when a melody note has already been tied over for three or more beats, allowing an essential 3rd or 7th to meet that pitch without building a voice *above* it.
* **Span and spacing:** The right hand stays within a major 9th of the melody's top pitch and maintains at least a minor 3rd above the left-hand tenor.
* **Color tone choices by harmony:**
  * *Major chords:* Favor a single color tone—typically the 6th or 9th—rather than stacking both.
  * *Minor 7th chords:* Favor the 5th or 9th (or 4th, 9th, and 5th on minor-6th chords).
  * *Half-diminished chords:* Include the `b5` if not already sounding, or add the 9th or 11th.
  * *Diminished 7th chords:* Balance chord tones evenly across the register, or introduce a whole-step upper neighbor color when appropriate.
  * *Dominant 7th chords:* Use natural 9 or 13 on non-resolving dominants or secondary `II7` chords, and altered colors (`b9` or `b13`) when resolving down a fifth—unless the melody already states the natural extension.
* **Honoring explicit chord symbols:**
  * *`aug`, `+`, or `#5`:* Actively includes the `#5` whenever range and melody allow.
  * *`alt`:* Avoids unaltered color tones (no natural 9, natural 13, or plain 5).
  * *`add` chords (e.g., `add9`):* Treats the chord as a triad plus the added color tone rather than turning it into a seventh chord.
  * *Tritone substitutions:* Dominants descending by half step favor `#11` color.
* **Avoiding wide 6th-chord gaps:** If adding a 6th would leave more than an octave between the left-hand tenor and the lowest right-hand note, the plugin falls back to the 5th when it gives tighter spacing.

---

## 3. Voice Leading Across Changes

When chords move from bar to bar, the plugin favors smooth motion over big leaps:

* **Minimal motion:** Common tones stay put and voices move by step whenever possible.
* **Fifth resolutions:** On roots moving down a fifth (`ii7–V7–I`), the 7th resolves down smoothly to the 3rd of the next chord.
* **Chromatic dominant runs:** Descending half-step dominant chains keep guide tones moving smoothly by semitone rather than jumping octaves.
* **Repeated chords:** Repeated measures hold the same shell and register unless alternating 3rd and 7th across longer spans.

---

## 4. Beat-3 Motion, Section Breaks, and Endings

On longer chords (full 4/4 measures or two-bar 3/4 spans), the accompaniment often adds gentle mid-measure motion—checked against the melody notes in the *second half* of the bar so it doesn't collide:

* **Inner/upper-voice steps:** Depending on chord type, a single voice may step halfway through—such as `7–6` or `6–5` on major/6th chords, `4–3`, `9–b9`, or `13–b13` on dominants, or `4–b3` and `9–1` on minor 7ths. If `b9` or `13` is explicitly requested in the chord symbol, it stays static rather than turning into a `9–b9` or `13–b13` line, letting another voice or the bass provide motion instead.
* **Beat-3 bass motion:** When no upper-voice step fits, beat 3 may step (using a chord tone of the current chord) toward the next chord's bass, move to the 5th on multi-bar or same-root chords, or drop an octave.
* **Section breaks and final chords:** Optional parenthesized turnarounds at the end of a piece or before a section break are ignored so the tonic chord sustains through the final melody note. On section-ending and final chords, the full voicing is stated once without upper-voice moving lines, at most dropping only the root an octave lower on beat 3 or tied bars until the melody concludes.