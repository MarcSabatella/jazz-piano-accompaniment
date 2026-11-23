import QtQuick 2.9
import MuseScore 3.0

MuseScore {
    menuPath: "Plugins.Jazz Piano Accompaniment"
    description: "Realizes lead sheet chord symbols into a 2-hand piano voicing accompaniment."
    version: "1.0.10"

    // --- TPC & Pitch Helpers ---

    function noteNameToTpc(letter, accidental) {
        var baseMap = { "F": 13, "C": 14, "G": 15, "D": 16, "A": 17, "E": 18, "B": 19 };
        var tpc = baseMap[letter.toUpperCase()];
        if (accidental === "#" || accidental === "♯") tpc += 7;
        else if (accidental === "##" || accidental === "𝄪") tpc += 14;
        else if (accidental === "b" || accidental === "♭") tpc -= 7;
        else if (accidental === "bb" || accidental === "𝄫") tpc -= 14;
        return tpc;
    }

    function tpcToPc(tpc) {
        return (((tpc - 14) * 7) % 12 + 12) % 12;
    }

    function isOpenKeySig(keySig) {
        return keySig === undefined || keySig === null || keySig < -7 || keySig > 7;
    }

    function parseChordSymbol(text) {
        if (!text) return null;
        var trimmed = text.trim();
        if (!trimmed) return null;

        var startsWithOpenParen = (trimmed.charAt(0) === "(");
        var endsWithCloseParen = (trimmed.charAt(trimmed.length - 1) === ")");

        var clean = trimmed.replace(/[()]/g, "");
        if (!clean) return null;

        var slashParts = clean.split("/");
        var mainPart = slashParts[0];
        var bassStr = slashParts.length > 1 ? slashParts[1] : null;

        var rootMatch = mainPart.match(/^([A-Ga-g])([#b♯♭]{0,2})(.*)$/);
        if (!rootMatch) return null;

        var rootTpc = noteNameToTpc(rootMatch[1], rootMatch[2]);
        var suffix = rootMatch[3];
        var bassTpc = rootTpc;

        if (bassStr) {
            var bassMatch = bassStr.match(/^([A-Ga-g])([#b♯♭]{0,2})/);
            if (bassMatch) {
                bassTpc = noteNameToTpc(bassMatch[1], bassMatch[2]);
            }
        }

        var isDim = /^(dim|o|°)/.test(suffix);
        var isAug = /^(\+|aug)/.test(suffix);
        var isMajQual = /^(maj|ma(?!j)|M(?=[6791Δt^]|$)|Δ|t(?=[6791]|$)|\^)/.test(suffix);
        var isMin = !isDim && !isMajQual && /^(m(?!a)|min|mi|-)/.test(suffix);
        var isSus = /sus/.test(suffix);

        var extPart = suffix;
        if (isDim) extPart = suffix.replace(/^(dim7|dim|o7|o|°7|°)/, "");
        else if (isMajQual) extPart = suffix.replace(/^(maj|ma(?!j)|M(?=[6791Δt^]|$)|Δ|t(?=[6791]|$)|\^)/, "");
        else if (isMin) extPart = suffix.replace(/^(min|mi|m|-)/, "");

        var hasFlat5 = isDim || /(b5|♭5|-5)/.test(extPart);
        var isHalfDim = /m(in|i)?7b5|-7b5|ø/.test(suffix) || (isMin && hasFlat5);
        var hasSharp5 = isAug || /(#5|♯5|\+5)/.test(extPart);
        var isAlt = /alt/.test(suffix);

        var isSixthChord = /(^|[^b#♯♭+-])6/.test(extPart) && !/7|11|13/.test(extPart);

        var hasFlat9 = /(b9|♭9|-9)/.test(extPart);
        var hasSharp9 = /(#9|♯9|\+9)/.test(extPart);
        var hasNat9 = !hasFlat9 && !hasSharp9 && /(^|[^0-9])9/.test(extPart);
        var hasSharp11 = /(#11|♯11|\+11)/.test(extPart);
        var hasNat11 = !hasSharp11 && /11/.test(extPart);
        var hasFlat13 = /(b13|♭13|-13|b6|♭6|-6)/.test(extPart);
        var hasNat13 = !hasFlat13 && /13/.test(extPart);

        var explicitSeventh = null;
        if (!isDim && (/(maj|ma(?!j)|M(?=[6791]|$)|Δ|(^|[^a-zA-Z])t(?=[6791]|$)|\^|j7)/.test(extPart) || isMajQual)) {
            explicitSeventh = "maj7";
        } else if (/dim7|o7|°7/.test(suffix)) {
            explicitSeventh = "dim7";
        } else if (isHalfDim) {
            explicitSeventh = "m7";
        } else if (isAlt) {
            explicitSeventh = "dom7";
        } else if (isSixthChord) {
            explicitSeventh = isMin ? "min6" : "maj7";
        } else if (/7|9|11|13/.test(extPart)) {
            explicitSeventh = isMin ? "m7" : "dom7";
        }

        return {
            raw: clean,
            startsWithOpenParen: startsWithOpenParen,
            endsWithCloseParen: endsWithCloseParen,
            rootTpc: rootTpc,
            bassTpc: bassTpc,
            isDim: isDim,
            isAug: isAug,
            isMin: isMin,
            isSus: isSus,
            isHalfDim: isHalfDim,
            hasFlat5: hasFlat5,
            hasSharp5: hasSharp5,
            isAlt: isAlt,
            isSixthChord: isSixthChord,
            hasFlat9: hasFlat9,
            hasSharp9: hasSharp9,
            hasNat9: hasNat9,
            hasSharp11: hasSharp11,
            hasNat11: hasNat11,
            hasFlat13: hasFlat13,
            hasNat13: hasNat13,
            explicitSeventh: explicitSeventh
        };
    }

    function filterOptionalEndTurnarounds(events, measures, scoreEndTick) {
        if (events.length <= 1) return events;

        var sectionEndTicks = [scoreEndTick];
        for (var m = 0; m < measures.length; m++) {
            if (measures[m].hasSectionBreak) {
                sectionEndTicks.push(measures[m].endTick);
            }
        }

        var skipEvent = [];
        for (var i = 0; i < events.length; i++) skipEvent.push(false);

        for (var b = 0; b < sectionEndTicks.length; b++) {
            var boundaryTick = sectionEndTicks[b];
            var lastIdx = -1;
            for (var e = 0; e < events.length; e++) {
                if (events[e].tick < boundaryTick) {
                    lastIdx = e;
                } else {
                    break;
                }
            }
            if (lastIdx <= 0) continue;

            var closeEv = events[lastIdx];
            if (closeEv.chord.startsWithOpenParen && closeEv.chord.endsWithCloseParen) {
                skipEvent[lastIdx] = true;
            } else if (closeEv.chord.endsWithCloseParen) {
                var openIdx = -1;
                for (var k = lastIdx - 1; k >= 1; k--) {
                    var crossedSection = false;
                    for (var sb = 0; sb < sectionEndTicks.length; sb++) {
                        if (sectionEndTicks[sb] > events[k].tick && sectionEndTicks[sb] < boundaryTick) {
                            crossedSection = true;
                            break;
                        }
                    }
                    if (crossedSection) break;

                    if (events[k].chord.startsWithOpenParen) {
                        openIdx = k;
                        break;
                    }
                }
                if (openIdx > 0) {
                    for (var s = openIdx; s <= lastIdx; s++) {
                        skipEvent[s] = true;
                    }
                }
            } else if (closeEv.chord.startsWithOpenParen) {
                skipEvent[lastIdx] = true;
            }
        }

        var filtered = [];
        for (var idx = 0; idx < events.length; idx++) {
            if (skipEvent[idx]) {
                if (events[idx].harmonyEl && events[idx].harmonyEl.play !== undefined) {
                    events[idx].harmonyEl.play = false;
                }
            } else {
                filtered.push(events[idx]);
            }
        }
        return filtered.length > 0 ? filtered : events;
    }

    function getChordToneTpcs(chord, keySig) {
        var thirdOffset = chord.isSus ? -1 : ((chord.isMin || chord.isDim) ? -3 : 4);
        var fifthOffset = chord.hasFlat5 ? -6 : (chord.hasSharp5 ? 8 : 1);
        var seventhOffset = -2;
        var resolvedSeventhType = chord.explicitSeventh;

        if (chord.isDim) {
            seventhOffset = -9;
            resolvedSeventhType = "dim7";
        } else if (chord.explicitSeventh === "min6") {
            seventhOffset = 3;
        } else if (chord.explicitSeventh === "maj7") {
            seventhOffset = 5;
        } else if (chord.explicitSeventh === "dom7" || chord.explicitSeventh === "m7") {
            seventhOffset = -2;
        } else if (!isOpenKeySig(keySig)) {
            var tonicTpc = 14 + keySig;
            var fifthsFromTonic = chord.rootTpc - tonicTpc;
            if (!chord.isMin && (fifthsFromTonic === 0 || fifthsFromTonic === -1)) {
                seventhOffset = 5;
                resolvedSeventhType = "maj7";
            } else if (!chord.isMin && (fifthsFromTonic === 1 || fifthsFromTonic === 2 || fifthsFromTonic === 3)) {
                seventhOffset = -2;
                resolvedSeventhType = "dom7";
            } else if (chord.isMin && (fifthsFromTonic === 2 || fifthsFromTonic === 3 || fifthsFromTonic === 4)) {
                seventhOffset = -2;
                resolvedSeventhType = "m7";
            } else {
                seventhOffset = -2;
                resolvedSeventhType = null;
            }
        } else {
            seventhOffset = -2;
            resolvedSeventhType = null;
        }

        return {
            rootTpc: chord.rootTpc,
            thirdTpc: chord.rootTpc + thirdOffset,
            fifthTpc: chord.rootTpc + fifthOffset,
            seventhTpc: chord.rootTpc + seventhOffset,
            resolvedSeventhType: resolvedSeventhType
        };
    }

    function annotateChromaticDomChains(events) {
        var domFlags = [];
        var inEvenDomChain = [];
        for (var i = 0; i < events.length; i++) {
            var ev = events[i];
            var tones = getChordToneTpcs(ev.chord, ev.keySig);
            var isDom = (tones.resolvedSeventhType === "dom7" && !ev.chord.isMin && !ev.chord.isDim && !ev.chord.isSus &&
                         tpcToPc(ev.chord.bassTpc) === tpcToPc(ev.chord.rootTpc));
            domFlags.push(isDom);
            inEvenDomChain.push(false);
            ev.isTritoneSub = false;
            ev.keepFifthFromPrevSharp11 = false;
        }

        var idx = 0;
        while (idx < events.length) {
            if (!domFlags[idx]) {
                idx++;
                continue;
            }
            var runStart = idx;
            var runEnd = idx;
            while (runEnd + 1 < events.length && domFlags[runEnd + 1]) {
                var prevRootPc = tpcToPc(events[runEnd].chord.rootTpc);
                var currRootPc = tpcToPc(events[runEnd + 1].chord.rootTpc);
                if (((prevRootPc - currRootPc + 12) % 12) === 1) {
                    runEnd++;
                } else {
                    break;
                }
            }

            var runLen = runEnd - runStart + 1;
            if (runLen >= 2 && (runLen % 2 === 0)) {
                for (var k = 0; k < runLen; k++) {
                    inEvenDomChain[runStart + k] = true;
                    if (k % 2 === 0) {
                        events[runStart + k].isTritoneSub = true;
                    } else {
                        events[runStart + k].keepFifthFromPrevSharp11 = true;
                    }
                }
            }
            idx = runEnd + 1;
        }

        for (var j = 0; j + 1 < events.length; j++) {
            if (!domFlags[j] || inEvenDomChain[j]) continue;
            var rPc = tpcToPc(events[j].chord.rootTpc);
            var nextRPc = tpcToPc(events[j + 1].chord.rootTpc);
            if (((rPc - nextRPc + 12) % 12) === 1) {
                events[j].isTritoneSub = true;
            }
        }
    }

    function placePcAtOrAbove(pc, floorMidi) {
        for (var m = floorMidi; m < floorMidi + 12; m++) {
            if (m % 12 === pc) return m;
        }
        return floorMidi;
    }

    function placePcAtOrBelow(pc, ceilingMidi) {
        for (var m = ceilingMidi; m > ceilingMidi - 12; m--) {
            if (m % 12 === pc) return m;
        }
        return ceilingMidi;
    }

    function placeRhPitchNearMelody(pc, floorMidi, ceilingMidi, melodyHighestMidi) {
        var base = placePcAtOrAbove(pc, floorMidi);
        if (base > ceilingMidi) return -1;

        var best = base;
        var candidate = base + 12;
        while (candidate <= ceilingMidi) {
            if (melodyHighestMidi < 127 && (melodyHighestMidi - best) > 14) {
                best = candidate;
            }
            candidate += 12;
        }
        return best;
    }

    function conflictsWithMelodyAlteration(candidateTpc, chord, melodyInfo) {
        var rootPc = tpcToPc(chord.rootTpc);
        var candPc = tpcToPc(candidateTpc);
        var intervalFromRoot = (candPc - rootPc + 12) % 12;

        var degreeGroups = chord.isMin
            ? [
                [1, 2],
                [3, 4],
                [5, 6],
                [6, 7],
                [8, 9],
                [10, 11]
              ]
            : [
                [1, 2, 3],
                [3, 4],
                [5, 6],
                [6, 7],
                [8, 9],
                [10, 11]
              ];

        for (var g = 0; g < degreeGroups.length; g++) {
            var grp = degreeGroups[g];
            if (grp.indexOf(intervalFromRoot) === -1) continue;

            for (var k = 0; k < grp.length; k++) {
                var otherInterval = grp[k];
                if (otherInterval === intervalFromRoot) continue;
                var otherPc = (rootPc + otherInterval) % 12;
                if ((melodyInfo.pcDurations[otherPc] || 0) > 0) {
                    return true;
                }
            }
        }
        return false;
    }

    function buildInvertedRhChord(primaryTpc, secondaryTpc, floorMidi, ceilingMidi, melodyInfo) {
        var notes = [];
        var primPc = tpcToPc(primaryTpc);
        var primMidi = placeRhPitchNearMelody(primPc, floorMidi, ceilingMidi, melodyInfo.highestMidi);

        if (primMidi !== -1) {
            notes.push({ pitch: primMidi, tpc: primaryTpc });

            if (secondaryTpc !== null) {
                var secPc = tpcToPc(secondaryTpc);
                var secProminent = ((melodyInfo.pcDurations[secPc] || 0) / melodyInfo.totalTicks) >= 0.25;
                if (!secProminent) {
                    var secAbove = placePcAtOrAbove(secPc, primMidi + 1);
                    if (secAbove <= ceilingMidi) {
                        notes.push({ pitch: secAbove, tpc: secondaryTpc });
                    } else {
                        var secBelow = placePcAtOrBelow(secPc, primMidi - 1);
                        if (secBelow >= floorMidi && secBelow <= ceilingMidi) {
                            notes.push({ pitch: secBelow, tpc: secondaryTpc });
                        }
                    }
                }
            }
        } else if (secondaryTpc !== null) {
            var fallbackPc = tpcToPc(secondaryTpc);
            var fallbackMidi = placeRhPitchNearMelody(fallbackPc, floorMidi, ceilingMidi, melodyInfo.highestMidi);
            if (fallbackMidi !== -1) {
                notes.push({ pitch: fallbackMidi, tpc: secondaryTpc });
            }
        }

        return notes;
    }

    function generateLhCandidates(bassTpc, tenorTpc, tenorRole, maxTenorMidi) {
        var bassPc = tpcToPc(bassTpc);
        var tenorPc = tpcToPc(tenorTpc);
        var all = [];
        var belowMelody = [];

        for (var b = 36; b <= 58; b++) {
            if (b % 12 !== bassPc) continue;

            var t = placePcAtOrAbove(tenorPc, b + 3);
            var span = t - b;
            if (span > 16) continue;
            if (t < 49) continue;

            if (span > 12 && (b + 12) < 55) continue;

            var cand = {
                bassMidi: b,
                bassTpc: bassTpc,
                tenorMidi: t,
                tenorTpc: tenorTpc,
                role: tenorRole,
                isTenth: (span > 12)
            };
            all.push(cand);
            if (maxTenorMidi === undefined || t <= maxTenorMidi) {
                belowMelody.push(cand);
            }
        }

        return (belowMelody.length > 0) ? belowMelody : all;
    }

    function pickBestLhCandidate(candidates, prevBassMidi, prevTenorMidi, thirdBonus, seventhBonus, melodyHighestMidi, requiredRhPc, rhCeiling, rootMotionInfo, roleToRhPcMap) {
        if (candidates.length === 0) return null;

        var best = null;
        var bestScore = -999999;

        var isSameRoot = rootMotionInfo ? rootMotionInfo.isSameRoot : false;
        var isDownFifth = rootMotionInfo ? rootMotionInfo.isDownFifth : false;
        var isStepwiseRoot = rootMotionInfo ? rootMotionInfo.isStepwiseRoot : false;
        var prevRole = rootMotionInfo ? rootMotionInfo.prevRole : null;

        for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i];
            var score = 0;

            if (c.role === "third") score += thirdBonus;
            if (c.role === "seventh") score += seventhBonus;
            if (c.role === "fifth") score += 10;

            if (c.bassMidi >= 41 && c.bassMidi <= 54) {
                score += 24;
            } else if (c.bassMidi < 41) {
                score -= (41 - c.bassMidi) * 1.5;
            } else {
                score -= 22 + (c.bassMidi - 55) * 14.0;
            }

            var neededPc = requiredRhPc;
            if ((neededPc === undefined || neededPc === -1) && roleToRhPcMap && roleToRhPcMap[c.role] !== undefined) {
                neededPc = roleToRhPcMap[c.role];
            }
            if (neededPc !== undefined && neededPc !== -1 && rhCeiling !== undefined) {
                var testRh = placePcAtOrAbove(neededPc, c.tenorMidi + 3);
                if (testRh <= rhCeiling) {
                    score += 55;
                } else {
                    score -= 95;
                }
            }

            if (prevBassMidi !== -1) {
                var bassInterval = Math.abs(c.bassMidi - prevBassMidi);
                if (bassInterval === 0) {
                    score += isSameRoot ? 65 : 25;
                } else if (bassInterval <= 2) {
                    score += isStepwiseRoot ? 45 : 38;
                } else if (bassInterval >= 10) {
                    score -= 18;
                }
            }

            if (prevTenorMidi !== -1) {
                var tenorInterval = Math.abs(c.tenorMidi - prevTenorMidi);

                if (isStepwiseRoot) {
                    if (tenorInterval === 0) {
                        score += 55;
                    } else if (tenorInterval <= 2) {
                        score += 85 - tenorInterval * 5;
                    } else {
                        score -= tenorInterval * 6.0;
                    }
                } else if (isDownFifth) {
                    if (prevRole === "seventh" && c.role === "third") {
                        if (tenorInterval <= 2) {
                            score += 60;
                        } else {
                            score -= 70;
                        }
                    } else if (prevRole === "seventh" && c.role === "seventh") {
                        score += 40;
                    } else if (tenorInterval === 0) {
                        score += 55;
                    } else if (tenorInterval <= 2) {
                        score += 35;
                    } else {
                        score -= tenorInterval * 2.0;
                    }
                } else {
                    if (tenorInterval === 0) {
                        score += isSameRoot ? 65 : 48;
                    } else if (tenorInterval <= 2) {
                        score += (isSameRoot ? 55 : 32) - tenorInterval * 2;
                    } else {
                        score -= tenorInterval * (isSameRoot ? 4.0 : 2.0);
                    }
                }
            }

            if (melodyHighestMidi >= 67 && melodyHighestMidi < 127) {
                var gap = melodyHighestMidi - c.tenorMidi;
                if (gap > 18) {
                    score -= (gap - 18) * 0.4;
                }
            }

            if (score > bestScore) {
                bestScore = score;
                best = c;
            }
        }

        return best;
    }

    function scoreSpreadEvenness(pitches) {
        if (pitches.length < 2) return 0;
        var sorted = pitches.slice().sort(function(a, b) { return a - b; });
        var intervals = [];
        var sum = 0;
        for (var i = 1; i < sorted.length; i++) {
            var diff = sorted[i] - sorted[i - 1];
            intervals.push(diff);
            sum += diff;
        }
        var mean = sum / intervals.length;
        var sqDev = 0;
        for (var j = 0; j < intervals.length; j++) {
            var d = intervals[j] - mean;
            sqDev += d * d;
        }
        return -sqDev;
    }

    function voiceDiminishedSeventh(chord, tones, prevBassMidi, prevLhTenorMidi, melodyInfo, rhCeiling) {
        var dimTones = [tones.rootTpc, tones.thirdTpc, tones.fifthTpc, tones.seventhTpc];
        var bassPc = tpcToPc(chord.bassTpc);
        var rootPc = tpcToPc(tones.rootTpc);

        var melodyDoublesBass = ((melodyInfo.pcDurations[bassPc] || 0) / melodyInfo.totalTicks) >= 0.25;

        var melodyHasDimColor = false;
        for (var d = 0; d < dimTones.length; d++) {
            var colorPc = (tpcToPc(dimTones[d]) + 2) % 12;
            if (((melodyInfo.pcDurations[colorPc] || 0) / melodyInfo.totalTicks) >= 0.25) {
                melodyHasDimColor = true;
                break;
            }
        }

        var remainingTones = [];
        for (var i = 0; i < dimTones.length; i++) {
            var pc = tpcToPc(dimTones[i]);
            if (pc === bassPc) continue;
            var inMel = ((melodyInfo.pcDurations[pc] || 0) / melodyInfo.totalTicks) >= 0.25;
            if (!inMel) {
                remainingTones.push(dimTones[i]);
            }
        }
        if (remainingTones.length < 2) {
            for (var k = 0; k < dimTones.length; k++) {
                var pcK = tpcToPc(dimTones[k]);
                if (pcK !== bassPc && remainingTones.indexOf(dimTones[k]) === -1) {
                    remainingTones.push(dimTones[k]);
                }
            }
        }

        var melAnchor = (melodyInfo.lowestMidi < 127) ? melodyInfo.lowestMidi : 72;

        if (melodyDoublesBass || melodyHasDimColor) {
            var bestFull = null;
            var bestFullScore = -999999;

            for (var tIdx = 0; tIdx < remainingTones.length; tIdx++) {
                var tenorTpc = remainingTones[tIdx];
                var lhCands = generateLhCandidates(chord.bassTpc, tenorTpc, "dim", rhCeiling);
                for (var c = 0; c < lhCands.length; c++) {
                    var lh = lhCands[c];
                    var rhNotes = [];
                    var pitchesForSpread = [lh.bassMidi, lh.tenorMidi];
                    var includesRoot = (tpcToPc(tenorTpc) === rootPc);

                    for (var rIdx = 0; rIdx < remainingTones.length; rIdx++) {
                        if (rIdx === tIdx) continue;
                        var rTpc = remainingTones[rIdx];
                        var rMidi = placePcAtOrAbove(tpcToPc(rTpc), lh.tenorMidi + 3);
                        if (rMidi <= rhCeiling) {
                            rhNotes.push({ pitch: rMidi, tpc: rTpc });
                            pitchesForSpread.push(rMidi);
                            if (tpcToPc(rTpc) === rootPc) includesRoot = true;
                        }
                    }
                    pitchesForSpread.push(melAnchor);

                    var sc = scoreSpreadEvenness(pitchesForSpread) + rhNotes.length * 55;
                    if (includesRoot) sc += 30;
                    if (lh.bassMidi >= 41 && lh.bassMidi <= 54) sc += 20;
                    if (prevBassMidi !== -1 && Math.abs(lh.bassMidi - prevBassMidi) <= 2) sc += 25;

                    if (sc > bestFullScore) {
                        bestFullScore = sc;
                        bestFull = { lhVoicing: lh, rhNotesSpec: rhNotes };
                    }
                }
            }

            if (bestFull) return bestFull;
        }

        var bestColored = null;
        var bestColoredScore = -999999;

        for (var iTen = 0; iTen < remainingTones.length; iTen++) {
            var candTenorTpc = remainingTones[iTen];
            var lhList = generateLhCandidates(chord.bassTpc, candTenorTpc, "dim", rhCeiling);

            for (var iRem = 0; iRem < remainingTones.length; iRem++) {
                if (iRem === iTen && remainingTones.length > 1) continue;
                var replacedToneTpc = remainingTones[iRem];
                var auxColorTpc = replacedToneTpc + 2;
                var auxColorPc = tpcToPc(auxColorTpc);

                for (var l = 0; l < lhList.length; l++) {
                    var lhCand = lhList[l];
                    var rhMidi = placePcAtOrAbove(auxColorPc, lhCand.tenorMidi + 3);
                    if (rhMidi > rhCeiling) {
                        var rhAlt = placePcAtOrBelow(auxColorPc, rhCeiling);
                        if (rhAlt >= lhCand.tenorMidi + 2) rhMidi = rhAlt;
                    }

                    var rhList = [];
                    var spreadPitches = [lhCand.bassMidi, lhCand.tenorMidi];
                    if (rhMidi >= lhCand.tenorMidi + 2 && rhMidi <= rhCeiling) {
                        rhList.push({ pitch: rhMidi, tpc: auxColorTpc });
                        spreadPitches.push(rhMidi);
                    }
                    spreadPitches.push(melAnchor);

                    var score = scoreSpreadEvenness(spreadPitches) + rhList.length * 60;
                    if (lhCand.bassMidi >= 41 && lhCand.bassMidi <= 54) score += 18;
                    if (prevBassMidi !== -1 && Math.abs(lhCand.bassMidi - prevBassMidi) <= 2) score += 20;
                    if (prevLhTenorMidi !== -1 && Math.abs(lhCand.tenorMidi - prevLhTenorMidi) <= 2) score += 15;

                    if (score > bestColoredScore) {
                        bestColoredScore = score;
                        bestColored = { lhVoicing: lhCand, rhNotesSpec: rhList };
                    }
                }
            }
        }

        return bestColored;
    }

    function scoreRhPair(primaryPitch, colorPitch, isAbovePrimary, prevRhCenterMidi, melodyHighestMidi, forceAbovePref) {
        var score = isAbovePrimary ? 6 : 0;

        if (forceAbovePref !== null && forceAbovePref !== undefined) {
            if (isAbovePrimary === forceAbovePref) score += 80;
            else score -= 80;
        }

        var center = (primaryPitch + colorPitch) / 2.0;
        if (prevRhCenterMidi !== -1) {
            var move = Math.abs(center - prevRhCenterMidi);
            score -= move * 3.0;
        }

        var lowPitch = Math.min(primaryPitch, colorPitch);
        if (melodyHighestMidi >= 67 && melodyHighestMidi < 127 && (melodyHighestMidi - lowPitch) > 14) {
            score -= ((melodyHighestMidi - lowPitch) - 14) * 1.2;
        }

        return score;
    }

    function getExplicitExtensionTpc(chord, melodyInfo) {
        var candidates = [];
        if (chord.hasFlat9) candidates.push(chord.rootTpc - 5);
        if (chord.hasSharp9) candidates.push(chord.rootTpc + 9);
        if (chord.hasNat9) candidates.push(chord.rootTpc + 2);
        if (chord.hasSharp11) candidates.push(chord.rootTpc + 6);
        if (chord.hasNat11) candidates.push(chord.rootTpc - 1);
        if (chord.hasFlat13) candidates.push(chord.rootTpc - 4);
        if (chord.hasNat13) candidates.push(chord.rootTpc + 3);

        for (var i = 0; i < candidates.length; i++) {
            var extPc = tpcToPc(candidates[i]);
            var inMelody = ((melodyInfo.pcDurations[extPc] || 0) / melodyInfo.totalTicks) >= 0.25;
            if (!inMelody && !conflictsWithMelodyAlteration(candidates[i], chord, melodyInfo)) {
                return candidates[i];
            }
        }
        return null;
    }

    // --- Color Tone Selection (Root-Position Chords) ---

    function selectRhColorNote(chord, tones, keySig, nextChord, lhVoicing, rhPrimary, rhPrimaryRole, rhCeiling, isVirtualMelodyRh, melodyInfo, prevRhCenterMidi, forceAbovePref, forceExtensionMode, chainFlags) {
        var rhFloor = lhVoicing.tenorMidi + 2;

        function placeSingleTargetTpc(targetTpc) {
            if (targetTpc === null) return null;
            var tPc = tpcToPc(targetTpc);
            if (((melodyInfo.pcDurations[tPc] || 0) / melodyInfo.totalTicks) >= 0.25) return null;
            if (conflictsWithMelodyAlteration(targetTpc, chord, melodyInfo)) return null;

            var opts = [];
            if (!isVirtualMelodyRh) {
                var up = placePcAtOrAbove(tPc, rhPrimary.pitch + 1);
                if (up <= rhCeiling) opts.push({ pitch: up, tpc: targetTpc, above: true });
            }
            var dn = placePcAtOrBelow(tPc, rhPrimary.pitch - 1);
            if (dn >= rhFloor && dn <= rhCeiling) {
                opts.push({ pitch: dn, tpc: targetTpc, above: false });
            }

            if (opts.length === 1 || (opts.length > 0 && isVirtualMelodyRh)) {
                return { pitch: opts[0].pitch, tpc: opts[0].tpc, isAbove: opts[0].above };
            } else if (opts.length === 2) {
                var s0 = scoreRhPair(rhPrimary.pitch, opts[0].pitch, true, prevRhCenterMidi, melodyInfo.highestMidi, forceAbovePref);
                var s1 = scoreRhPair(rhPrimary.pitch, opts[1].pitch, false, prevRhCenterMidi, melodyInfo.highestMidi, forceAbovePref);
                var ch = (s1 > s0) ? opts[1] : opts[0];
                return { pitch: ch.pitch, tpc: ch.tpc, isAbove: ch.above };
            }
            return null;
        }

        function applyWideGapFifthFallback(chosenColor) {
            if (!chosenColor) return null;
            var isSixthColor = (tpcToPc(chosenColor.tpc) === tpcToPc(chord.rootTpc + 3));
            var lowestRh = Math.min(rhPrimary.pitch, chosenColor.pitch);
            if (isSixthColor && (lowestRh - lhVoicing.tenorMidi) > 12) {
                var fifthCandidate = placeSingleTargetTpc(tones.fifthTpc);
                if (fifthCandidate) {
                    var newLowest = Math.min(rhPrimary.pitch, fifthCandidate.pitch);
                    if (newLowest < lowestRh) {
                        return fifthCandidate;
                    }
                }
            }
            return chosenColor;
        }

        if (chord.isAlt) {
            var altCandidates = [
                chord.rootTpc - 5,
                chord.rootTpc - 4,
                chord.rootTpc + 9,
                chord.rootTpc + 6
            ];
            for (var ac = 0; ac < altCandidates.length; ac++) {
                var altRes = placeSingleTargetTpc(altCandidates[ac]);
                if (altRes) return altRes;
            }
            return null;
        }

        if (chainFlags) {
            if (chainFlags.isTritoneSub) {
                var sharp11Pick = placeSingleTargetTpc(chord.rootTpc + 6);
                if (sharp11Pick) return sharp11Pick;
            }
            if (chainFlags.keepFifthFromPrevSharp11) {
                var fifthPick = placeSingleTargetTpc(tones.fifthTpc);
                if (fifthPick) return fifthPick;
            }
        }

        if (chord.isSixthChord && chord.isMin) {
            var min6ColorCandidates = [chord.rootTpc + 5, chord.rootTpc + 2, tones.fifthTpc];
            for (var m6 = 0; m6 < min6ColorCandidates.length; m6++) {
                var m6Res = placeSingleTargetTpc(min6ColorCandidates[m6]);
                if (m6Res) return m6Res;
            }
            return null;
        }

        if (chord.isHalfDim) {
            var b5Tpc = tones.fifthTpc;
            var b5Pc = tpcToPc(b5Tpc);
            var b5AlreadySounding = (lhVoicing.bassMidi % 12 === b5Pc) ||
                                    (lhVoicing.tenorMidi % 12 === b5Pc) ||
                                    ((melodyInfo.pcDurations[b5Pc] || 0) > 0);

            if (!b5AlreadySounding) {
                var b5Res = placeSingleTargetTpc(b5Tpc);
                if (b5Res) return b5Res;
            }

            var hdCandidates = [chord.rootTpc + 2, chord.rootTpc - 1];
            for (var h = 0; h < hdCandidates.length; h++) {
                var hdRes = placeSingleTargetTpc(hdCandidates[h]);
                if (hdRes) return hdRes;
            }

            return null;
        }

        if (chord.isSus && rhPrimary.pitch > rhCeiling) {
            return placeSingleTargetTpc(tones.fifthTpc);
        }

        var explicitExtTpc = forceExtensionMode ? null : getExplicitExtensionTpc(chord, melodyInfo);
        if (explicitExtTpc !== null) {
            var extRes = placeSingleTargetTpc(explicitExtTpc);
            if (extRes) return extRes;
        }

        var hasRootInBass = (tpcToPc(chord.bassTpc) === tpcToPc(tones.rootTpc));
        var useAlteredByProgression = false;
        var resolvesDownFifth = false;
        var isDom7 = (tones.resolvedSeventhType === "dom7" && !chord.isMin && !chord.isDim && !chord.isSus);

        if (hasRootInBass && isDom7) {
            if (nextChord) {
                var rootPc = tpcToPc(chord.rootTpc);
                var nextRootPc = tpcToPc(nextChord.rootTpc);
                resolvesDownFifth = ((nextRootPc - rootPc + 12) % 12 === 5);

                var isDominantII7 = false;
                if (!isOpenKeySig(keySig)) {
                    var tonicTpc = 14 + keySig;
                    var fifthsFromTonic = chord.rootTpc - tonicTpc;
                    isDominantII7 = (fifthsFromTonic === 2);
                }

                if (resolvesDownFifth && !isDominantII7) {
                    useAlteredByProgression = true;
                }
            }
        }

        var nat9Pc = tpcToPc(chord.rootTpc + 2);
        var nat13Pc = tpcToPc(chord.rootTpc + 3);
        var nat9InMelody = (melodyInfo.pcDurations[nat9Pc] || 0) > 0;
        var nat13InMelody = (melodyInfo.pcDurations[nat13Pc] || 0) > 0;

        var useFlat9 = useAlteredByProgression && !nat9InMelody;
        var useFlat13 = useAlteredByProgression && !nat13InMelody;

        if (forceExtensionMode === "nat9") { useFlat9 = false; useFlat13 = false; }
        else if (forceExtensionMode === "flat9") { useFlat9 = !nat9InMelody; }

        var useFifth = (chord.isMin && !chord.hasFlat5 && !chord.isSixthChord) || chord.hasSharp5;
        var sixthTpc = useFlat13 ? (chord.rootTpc - 4) : (chord.rootTpc + 3);
        var fifthOrSixthTpc = useFifth ? tones.fifthTpc : sixthTpc;
        var ninthTpc = useFlat9 ? (chord.rootTpc - 5) : (chord.rootTpc + 2);

        if (!useFifth && conflictsWithMelodyAlteration(fifthOrSixthTpc, chord, melodyInfo)) {
            fifthOrSixthTpc = tones.fifthTpc;
        }
        if (conflictsWithMelodyAlteration(ninthTpc, chord, melodyInfo)) {
            ninthTpc = null;
        }

        var validOptions = [];

        if (!isVirtualMelodyRh) {
            var aboveColorTpc = (rhPrimaryRole === "seventh") ? ninthTpc : fifthOrSixthTpc;
            if (aboveColorTpc !== null && !conflictsWithMelodyAlteration(aboveColorTpc, chord, melodyInfo)) {
                var aboveColorPc = tpcToPc(aboveColorTpc);
                var aboveMidi = placePcAtOrAbove(aboveColorPc, rhPrimary.pitch + 1);
                if (aboveMidi <= rhCeiling) {
                    validOptions.push({ pitch: aboveMidi, tpc: aboveColorTpc, above: true });
                }
            }
        }

        var belowColorTpc = (rhPrimaryRole === "third") ? ninthTpc : fifthOrSixthTpc;
        if (belowColorTpc !== null && !conflictsWithMelodyAlteration(belowColorTpc, chord, melodyInfo)) {
            var belowColorPc = tpcToPc(belowColorTpc);
            var belowMidi = placePcAtOrBelow(belowColorPc, rhPrimary.pitch - 1);
            if (belowMidi >= rhFloor && belowMidi <= rhCeiling) {
                validOptions.push({ pitch: belowMidi, tpc: belowColorTpc, above: false });
            }
        }

        if (validOptions.length > 0) {
            if (validOptions.length === 1 || isVirtualMelodyRh) {
                return applyWideGapFifthFallback({ pitch: validOptions[0].pitch, tpc: validOptions[0].tpc, isAbove: validOptions[0].above });
            }
            var scoreAbove = scoreRhPair(rhPrimary.pitch, validOptions[0].pitch, true, prevRhCenterMidi, melodyInfo.highestMidi, forceAbovePref);
            var scoreBelow = scoreRhPair(rhPrimary.pitch, validOptions[1].pitch, false, prevRhCenterMidi, melodyInfo.highestMidi, forceAbovePref);
            var chosen = (scoreBelow > scoreAbove) ? validOptions[1] : validOptions[0];
            return applyWideGapFifthFallback({ pitch: chosen.pitch, tpc: chosen.tpc, isAbove: chosen.above });
        }

        if (hasRootInBass && isDom7 && !resolvesDownFifth) {
            var fallbackSharp11 = placeSingleTargetTpc(chord.rootTpc + 6);
            if (fallbackSharp11) return fallbackSharp11;
        }

        return null;
    }

    // --- Single-Bar Voicing Solver ---

    function computeBarVoicing(chord, tones, keySig, nextChord, prevChord, prevBassMidi, prevLhTenorMidi, prevLhRole, prevRhCenterMidi, prevRhColorAbove, barMelodyInfo, forceExtensionMode, overrideThirdRole, chainFlags) {
        var rootPc = tpcToPc(tones.rootTpc);
        var thirdPc = tpcToPc(tones.thirdTpc);
        var fifthPc = tpcToPc(tones.fifthTpc);
        var seventhPc = tpcToPc(tones.seventhTpc);
        var bassPc = tpcToPc(chord.bassTpc);
        var hasSeventh = (tones.resolvedSeventhType !== null);

        var prevRootPc = prevChord ? tpcToPc(prevChord.rootTpc) : -1;
        var rootDiffUp = (prevChord !== null) ? ((rootPc - prevRootPc + 12) % 12) : -1;
        var isSameRootSeq = (prevChord !== null &&
                             rootDiffUp === 0 &&
                             bassPc === rootPc &&
                             tpcToPc(prevChord.bassTpc) === prevRootPc);
        var isDownFifth = (prevChord !== null && rootDiffUp === 5);
        var isStepwiseRoot = (prevChord !== null && (rootDiffUp === 1 || rootDiffUp === 2 || rootDiffUp === 10 || rootDiffUp === 11));

        var rootMotionInfo = {
            isSameRoot: isSameRootSeq,
            isDownFifth: isDownFifth,
            isStepwiseRoot: isStepwiseRoot,
            prevRole: prevLhRole
        };

        var lhVoicing = null;
        var rhNotesSpec = [];
        var rhPrimaryRole = null;
        var rhTargetTpc = null;
        var allowExtraColorTone = true;
        var rhFloor = 0;
        var rhCeiling = barMelodyInfo.lowestMidi - 1;
        var currentColorAbove = null;

        if (chord.isDim) {
            allowExtraColorTone = false;
            var dimResult = voiceDiminishedSeventh(chord, tones, prevBassMidi, prevLhTenorMidi, barMelodyInfo, rhCeiling);
            if (dimResult) {
                lhVoicing = dimResult.lhVoicing;
                rhNotesSpec = dimResult.rhNotesSpec;
            }
        } else if (bassPc === thirdPc && bassPc !== rootPc) {
            allowExtraColorTone = false;
            var rootInMel = ((barMelodyInfo.pcDurations[rootPc] || 0) / barMelodyInfo.totalTicks) >= 0.25;
            var fifthInMel = ((barMelodyInfo.pcDurations[fifthPc] || 0) / barMelodyInfo.totalTicks) >= 0.25;
            var seventhInMel = hasSeventh && (((barMelodyInfo.pcDurations[seventhPc] || 0) / barMelodyInfo.totalTicks) >= 0.25);

            var cands3rdBass = generateLhCandidates(chord.bassTpc, tones.rootTpc, "root", rhCeiling);
            if (!fifthInMel) {
                cands3rdBass = cands3rdBass.concat(generateLhCandidates(chord.bassTpc, tones.fifthTpc, "fifth", rhCeiling));
            }

            var targetRhPc3 = (hasSeventh && !seventhInMel) ? seventhPc : (fifthInMel ? -1 : fifthPc);
            lhVoicing = pickBestLhCandidate(cands3rdBass, prevBassMidi, prevLhTenorMidi, 0, 0, barMelodyInfo.highestMidi, targetRhPc3, rhCeiling, { isSameRoot: false, isDownFifth: false, isStepwiseRoot: false, prevRole: prevLhRole }, null);

            rhFloor = lhVoicing.tenorMidi + 3;
            if (lhVoicing.role === "fifth") {
                var rhFrom5Tenor = (hasSeventh && !seventhInMel) ? tones.seventhTpc : (rootInMel ? null : tones.rootTpc);
                if (rhFrom5Tenor !== null) {
                    rhNotesSpec = buildInvertedRhChord(rhFrom5Tenor, null, rhFloor, rhCeiling, barMelodyInfo);
                }
            } else {
                if (hasSeventh && !seventhInMel) {
                    rhNotesSpec = buildInvertedRhChord(tones.seventhTpc, fifthInMel ? null : tones.fifthTpc, rhFloor, rhCeiling, barMelodyInfo);
                } else if (!fifthInMel) {
                    rhNotesSpec = buildInvertedRhChord(tones.fifthTpc, null, rhFloor, rhCeiling, barMelodyInfo);
                }
            }

            if (rhNotesSpec.length === 0 && !chord.isAlt) {
                var ninthTpcInv = chord.rootTpc + 2;
                var ninthPcInv = tpcToPc(ninthTpcInv);
                var ninthInMelInv = ((barMelodyInfo.pcDurations[ninthPcInv] || 0) / barMelodyInfo.totalTicks) >= 0.25;
                if (!ninthInMelInv && !conflictsWithMelodyAlteration(ninthTpcInv, chord, barMelodyInfo)) {
                    var ninthMidiInv = placeRhPitchNearMelody(ninthPcInv, lhVoicing.tenorMidi + 2, rhCeiling, barMelodyInfo.highestMidi);
                    if (ninthMidiInv !== -1) {
                        rhNotesSpec.push({ pitch: ninthMidiInv, tpc: ninthTpcInv });
                    }
                }
            }
        } else if (bassPc === fifthPc && bassPc !== rootPc) {
            allowExtraColorTone = false;
            var cands5thBass = generateLhCandidates(chord.bassTpc, tones.thirdTpc, "third", rhCeiling);
            var seventhProm = hasSeventh && (((barMelodyInfo.pcDurations[seventhPc] || 0) / barMelodyInfo.totalTicks) >= 0.25);
            var includeSeventh = hasSeventh && !seventhProm;
            var explicitExt5 = getExplicitExtensionTpc(chord, barMelodyInfo);
            var targetRhPc5 = includeSeventh ? seventhPc : (explicitExt5 !== null ? tpcToPc(explicitExt5) : rootPc);

            lhVoicing = pickBestLhCandidate(cands5thBass, prevBassMidi, prevLhTenorMidi, 0, 0, barMelodyInfo.highestMidi, targetRhPc5, rhCeiling, { isSameRoot: false, isDownFifth: false, isStepwiseRoot: false, prevRole: prevLhRole }, null);

            rhFloor = lhVoicing.tenorMidi + 3;
            rhNotesSpec = buildInvertedRhChord(
                tones.rootTpc,
                includeSeventh ? tones.seventhTpc : explicitExt5,
                rhFloor,
                rhCeiling,
                barMelodyInfo
            );
        } else if (bassPc === seventhPc && bassPc !== rootPc) {
            allowExtraColorTone = false;
            var cands7thBass = generateLhCandidates(chord.bassTpc, tones.thirdTpc, "third", rhCeiling);
            lhVoicing = pickBestLhCandidate(cands7thBass, prevBassMidi, prevLhTenorMidi, 0, 0, barMelodyInfo.highestMidi, rootPc, rhCeiling, { isSameRoot: false, isDownFifth: false, isStepwiseRoot: false, prevRole: prevLhRole }, null);

            rhFloor = lhVoicing.tenorMidi + 3;
            var fifthProm7 = ((barMelodyInfo.pcDurations[fifthPc] || 0) / barMelodyInfo.totalTicks) >= 0.25;
            rhNotesSpec = buildInvertedRhChord(
                tones.rootTpc,
                fifthProm7 ? null : tones.fifthTpc,
                rhFloor,
                rhCeiling,
                barMelodyInfo
            );
        } else {
            var thirdInFirstHalf = ((barMelodyInfo.firstHalfPcDurations[thirdPc] || 0) > 0);
            var seventhInFirstHalf = hasSeventh && ((barMelodyInfo.firstHalfPcDurations[seventhPc] || 0) > 0);

            var thirdProminent = thirdInFirstHalf && (((barMelodyInfo.pcDurations[thirdPc] || 0) / barMelodyInfo.totalTicks) >= 0.25);
            var seventhProminent = seventhInFirstHalf && (((barMelodyInfo.pcDurations[seventhPc] || 0) / barMelodyInfo.totalTicks) >= 0.25);

            var thirdIsStaleTied = (barMelodyInfo.staleTiedPcs[thirdPc] === true);
            var seventhIsStaleTied = hasSeventh && (barMelodyInfo.staleTiedPcs[seventhPc] === true);

            var effThirdProminent = thirdProminent && !thirdIsStaleTied;
            var effSeventhProminent = seventhProminent && !seventhIsStaleTied;

            var thirdBonus = 0;
            var seventhBonus = 0;

            if (effThirdProminent && !effSeventhProminent) seventhBonus += 100;
            else if (effSeventhProminent && !effThirdProminent) thirdBonus += 100;

            if (overrideThirdRole === "third") thirdBonus += 160;
            else if (overrideThirdRole === "seventh") seventhBonus += 160;
            else if (isSameRootSeq && prevLhRole !== null) {
                if (prevLhRole === "third") thirdBonus += 140;
                else if (prevLhRole === "seventh") seventhBonus += 140;
            }

            var allCands = generateLhCandidates(chord.bassTpc, tones.thirdTpc, "third", rhCeiling);
            if (hasSeventh) {
                allCands = allCands.concat(generateLhCandidates(chord.bassTpc, tones.seventhTpc, "seventh", rhCeiling));
            }

            var roleToRhPc = null;
            if (hasSeventh) {
                roleToRhPc = {
                    "third": effSeventhProminent ? -1 : seventhPc,
                    "seventh": effThirdProminent ? -1 : thirdPc
                };
            }

            var effectiveGuideCeiling = rhCeiling;
            if (hasSeventh && (thirdIsStaleTied || seventhIsStaleTied)) {
                var stalePc = seventhIsStaleTied ? seventhPc : thirdPc;
                if (barMelodyInfo.pcLowestMidi[stalePc] !== undefined) {
                    effectiveGuideCeiling = Math.max(rhCeiling, barMelodyInfo.pcLowestMidi[stalePc]);
                }
            }

            lhVoicing = pickBestLhCandidate(allCands, prevBassMidi, prevLhTenorMidi, thirdBonus, seventhBonus, barMelodyInfo.highestMidi, -1, effectiveGuideCeiling, rootMotionInfo, roleToRhPc);

            if (hasSeventh) {
                rhPrimaryRole = (lhVoicing.role === "third") ? "seventh" : "third";
                rhTargetTpc = (lhVoicing.role === "third") ? tones.seventhTpc : tones.thirdTpc;
            } else {
                rhPrimaryRole = "root";
                rhTargetTpc = tones.fifthTpc;
            }

            var rhTargetPc = tpcToPc(rhTargetTpc);
            rhFloor = lhVoicing.tenorMidi + 3;
            var guideCeiling = (barMelodyInfo.staleTiedPcs[rhTargetPc] === true)
                ? Math.max(rhCeiling, barMelodyInfo.pcLowestMidi[rhTargetPc])
                : rhCeiling;

            var rhMidi = placeRhPitchNearMelody(rhTargetPc, rhFloor, guideCeiling, barMelodyInfo.highestMidi);
            if (rhMidi !== -1) {
                rhNotesSpec.push({ pitch: rhMidi, tpc: rhTargetTpc });
            }
        }

        if (allowExtraColorTone && chord.isHalfDim && rhNotesSpec.length === 0) {
            var b5PcReq = tpcToPc(tones.fifthTpc);
            var b5Pitch = placeRhPitchNearMelody(b5PcReq, lhVoicing.tenorMidi + 3, rhCeiling, barMelodyInfo.highestMidi);
            if (b5Pitch !== -1) {
                rhNotesSpec.push({ pitch: b5Pitch, tpc: tones.fifthTpc });
                rhPrimaryRole = "fifth";
                rhTargetTpc = tones.fifthTpc;
            }
        }

        var forceAboveOrientation = isSameRootSeq ? prevRhColorAbove : null;
        if (allowExtraColorTone && rhPrimaryRole !== null && rhTargetTpc !== null) {
            if (rhNotesSpec.length === 1) {
                var colorNote = selectRhColorNote(
                    chord,
                    tones,
                    keySig,
                    nextChord,
                    lhVoicing,
                    rhNotesSpec[0],
                    rhPrimaryRole,
                    rhCeiling,
                    false,
                    barMelodyInfo,
                    prevRhCenterMidi,
                    forceAboveOrientation,
                    forceExtensionMode,
                    chainFlags
                );
                if (colorNote) {
                    rhNotesSpec.push({ pitch: colorNote.pitch, tpc: colorNote.tpc });
                    currentColorAbove = colorNote.isAbove;
                }
            } else if (rhNotesSpec.length === 0) {
                var missingPc = tpcToPc(rhTargetTpc);
                var melodyGuideMidi = barMelodyInfo.pcLowestMidi[missingPc];
                if (melodyGuideMidi !== undefined) {
                    var virtualRh = { pitch: melodyGuideMidi, tpc: rhTargetTpc };
                    var belowMelodyColor = selectRhColorNote(
                        chord,
                        tones,
                        keySig,
                        nextChord,
                        lhVoicing,
                        virtualRh,
                        rhPrimaryRole,
                        rhCeiling,
                        true,
                        barMelodyInfo,
                        prevRhCenterMidi,
                        null,
                        forceExtensionMode,
                        chainFlags
                    );
                    if (belowMelodyColor) {
                        rhNotesSpec.push({ pitch: belowMelodyColor.pitch, tpc: belowMelodyColor.tpc });
                        currentColorAbove = belowMelodyColor.isAbove;
                    }
                }
            }
        }

        return {
            lhVoicing: lhVoicing,
            rhNotesSpec: rhNotesSpec,
            rhCeiling: rhCeiling,
            currentColorAbove: currentColorAbove
        };
    }

    // --- Moving Line Planners ---

    function planInnerOrUpperMotion(chord, tones, lhVoicing, rhNotesSpec, rhCeiling, melodyInfo, allowedKinds, chainFlags, secondHalfMelodyInfo) {
        var thirdPc = tpcToPc(tones.thirdTpc);
        var fifthPc = tpcToPc(tones.fifthTpc);
        var sixthPc = tpcToPc(chord.rootTpc + 3);
        var maj7Pc = tpcToPc(chord.rootTpc + 5);
        var nat9Pc = tpcToPc(chord.rootTpc + 2);
        var flat9Pc = tpcToPc(chord.rootTpc - 5);
        var nat13Pc = tpcToPc(chord.rootTpc + 3);
        var flat13Pc = tpcToPc(chord.rootTpc - 4);
        var sharp11Pc = tpcToPc(chord.rootTpc + 6);

        var secondHalfCeiling = (secondHalfMelodyInfo && secondHalfMelodyInfo.overallLowestMidi < 127)
            ? (secondHalfMelodyInfo.overallLowestMidi - 1)
            : rhCeiling;

        var lowestRhPitch = 127;
        for (var r = 0; r < rhNotesSpec.length; r++) {
            if (rhNotesSpec[r].pitch < lowestRhPitch) lowestRhPitch = rhNotesSpec[r].pitch;
        }

        function isKindAllowed(kind) {
            return !allowedKinds || allowedKinds.indexOf(kind) !== -1;
        }

        function isBlockedByMelody(tpc, allowIfExactInMelody) {
            var pc = tpcToPc(tpc);
            if (!allowIfExactInMelody && (melodyInfo.pcDurations[pc] || 0) > 0) {
                return true;
            }
            return conflictsWithMelodyAlteration(tpc, chord, melodyInfo);
        }

        function findRhNoteByPc(targetPc) {
            for (var i = 0; i < rhNotesSpec.length; i++) {
                if (rhNotesSpec[i].pitch % 12 === targetPc) {
                    return { index: i, note: rhNotesSpec[i] };
                }
            }
            return null;
        }

        function isCleanRhStep(firstPitch, secondPitch, excludeIdx) {
            if (firstPitch > rhCeiling || secondPitch > secondHalfCeiling) return false;
            if (firstPitch < lhVoicing.tenorMidi + 2 || secondPitch < lhVoicing.tenorMidi + 2) return false;
            for (var k = 0; k < rhNotesSpec.length; k++) {
                if (k === excludeIdx) continue;
                if (rhNotesSpec[k].pitch === firstPitch || rhNotesSpec[k].pitch === secondPitch) return false;
            }
            return true;
        }

        function isCleanLhTenorStep(firstPitch, secondPitch) {
            if (firstPitch < lhVoicing.bassMidi + 3 || secondPitch < lhVoicing.bassMidi + 3) return false;
            if (secondPitch < 49) return false;
            if (firstPitch >= lowestRhPitch - 1 || secondPitch >= lowestRhPitch - 1) return false;
            if (firstPitch > rhCeiling || secondPitch > secondHalfCeiling) return false;
            return true;
        }

        var isMaj7Family = (tones.resolvedSeventhType === "maj7" || tones.resolvedSeventhType === "min6" || chord.isSixthChord);
        if (isMaj7Family) {
            var maj7Tpc = chord.rootTpc + 5;
            var sixthTpc = chord.rootTpc + 3;
            var fifthTpc = tones.fifthTpc;
            var hitMaj7 = findRhNoteByPc(maj7Pc);
            var hit6 = findRhNoteByPc(sixthPc);
            var hit5 = findRhNoteByPc(fifthPc);

            if (isKindAllowed("7-6") && hitMaj7 && !isBlockedByMelody(maj7Tpc, false) && !isBlockedByMelody(sixthTpc, true)) {
                var target6Pitch = hitMaj7.note.pitch - 1;
                var dropStatic6Idx = (hit6 && hit6.index !== hitMaj7.index) ? hit6.index : -1;
                var validWithOmit = (hitMaj7.note.pitch <= rhCeiling && target6Pitch <= secondHalfCeiling && target6Pitch >= lhVoicing.tenorMidi + 2);
                for (var idxCheck = 0; idxCheck < rhNotesSpec.length; idxCheck++) {
                    if (idxCheck === hitMaj7.index || idxCheck === dropStatic6Idx) continue;
                    if (rhNotesSpec[idxCheck].pitch === hitMaj7.note.pitch || rhNotesSpec[idxCheck].pitch === target6Pitch) {
                        validWithOmit = false;
                    }
                }
                if (validWithOmit) {
                    return {
                        kind: "7-6",
                        repeatable: true,
                        staff: "rh",
                        movingIndex: hitMaj7.index,
                        omitRhIndex: dropStatic6Idx,
                        firstNote: { pitch: hitMaj7.note.pitch, tpc: maj7Tpc },
                        secondNote: { pitch: target6Pitch, tpc: sixthTpc }
                    };
                }
            }

            if (isKindAllowed("7-6") && hit6 && !isBlockedByMelody(maj7Tpc, false) && !isBlockedByMelody(sixthTpc, true)) {
                var startMaj7Pitch = hit6.note.pitch + 1;
                if (isCleanRhStep(startMaj7Pitch, hit6.note.pitch, hit6.index)) {
                    return {
                        kind: "7-6",
                        repeatable: true,
                        staff: "rh",
                        movingIndex: hit6.index,
                        omitRhIndex: -1,
                        firstNote: { pitch: startMaj7Pitch, tpc: maj7Tpc },
                        secondNote: { pitch: hit6.note.pitch, tpc: sixthTpc }
                    };
                }
            }

            if (isKindAllowed("7-6") && lhVoicing.tenorMidi % 12 === maj7Pc && !isBlockedByMelody(maj7Tpc, false) && !isBlockedByMelody(sixthTpc, true)) {
                var lhTarget6 = lhVoicing.tenorMidi - 1;
                if (isCleanLhTenorStep(lhVoicing.tenorMidi, lhTarget6)) {
                    return {
                        kind: "7-6",
                        repeatable: true,
                        staff: "lh",
                        movingIndex: 1,
                        omitRhIndex: hit6 ? hit6.index : -1,
                        firstNote: { pitch: lhVoicing.tenorMidi, tpc: maj7Tpc },
                        secondNote: { pitch: lhTarget6, tpc: sixthTpc }
                    };
                }
            }

            if (isKindAllowed("6-5") && hit6 && !isBlockedByMelody(sixthTpc, false) && !isBlockedByMelody(fifthTpc, true)) {
                var target5Pitch = hit6.note.pitch - 2;
                if (isCleanRhStep(hit6.note.pitch, target5Pitch, hit6.index)) {
                    return {
                        kind: "6-5",
                        repeatable: false,
                        staff: "rh",
                        movingIndex: hit6.index,
                        omitRhIndex: -1,
                        firstNote: { pitch: hit6.note.pitch, tpc: sixthTpc },
                        secondNote: { pitch: target5Pitch, tpc: fifthTpc }
                    };
                }
            }

            if (isKindAllowed("6-5") && hit5 && !isBlockedByMelody(sixthTpc, false) && !isBlockedByMelody(fifthTpc, true)) {
                var start6Pitch = hit5.note.pitch + 2;
                if (isCleanRhStep(start6Pitch, hit5.note.pitch, hit5.index)) {
                    return {
                        kind: "6-5",
                        repeatable: false,
                        staff: "rh",
                        movingIndex: hit5.index,
                        omitRhIndex: -1,
                        firstNote: { pitch: start6Pitch, tpc: sixthTpc },
                        secondNote: { pitch: hit5.note.pitch, tpc: fifthTpc }
                    };
                }
            }
        }

        var isDom7 = (tones.resolvedSeventhType === "dom7" && !chord.isMin && !chord.isDim);
        if (isDom7) {
            var nat9Tpc = chord.rootTpc + 2;
            var flat9Tpc = chord.rootTpc - 5;
            var nat13Tpc = chord.rootTpc + 3;
            var flat13Tpc = chord.rootTpc - 4;
            var fourthTpc = chord.rootTpc - 1;

            var hasSharp11InRh = (findRhNoteByPc(sharp11Pc) !== null);
            var block4To3 = hasSharp11InRh || (chainFlags && chainFlags.isTritoneSub);

            var hitB9 = findRhNoteByPc(flat9Pc);
            if (!chord.hasFlat9 && isKindAllowed("9-b9") && hitB9 && !isBlockedByMelody(nat9Tpc, false) && !isBlockedByMelody(flat9Tpc, false)) {
                var start9Pitch = hitB9.note.pitch + 1;
                if (isCleanRhStep(start9Pitch, hitB9.note.pitch, hitB9.index)) {
                    return {
                        kind: "9-b9",
                        repeatable: false,
                        staff: "rh",
                        movingIndex: hitB9.index,
                        omitRhIndex: -1,
                        firstNote: { pitch: start9Pitch, tpc: nat9Tpc },
                        secondNote: { pitch: hitB9.note.pitch, tpc: flat9Tpc }
                    };
                }
            }

            var explicit13 = chord.hasNat13 || chord.hasFlat13;
            var hitB13 = findRhNoteByPc(flat13Pc);
            if (!explicit13 && isKindAllowed("13-b13") && hitB13 && !isBlockedByMelody(nat13Tpc, false) && !isBlockedByMelody(flat13Tpc, false)) {
                var start13Pitch = hitB13.note.pitch + 1;
                if (isCleanRhStep(start13Pitch, hitB13.note.pitch, hitB13.index)) {
                    return {
                        kind: "13-b13",
                        repeatable: false,
                        staff: "rh",
                        movingIndex: hitB13.index,
                        omitRhIndex: -1,
                        firstNote: { pitch: start13Pitch, tpc: nat13Tpc },
                        secondNote: { pitch: hitB13.note.pitch, tpc: flat13Tpc }
                    };
                }
            }

            if (isKindAllowed("4-3") && !chord.isSus && !block4To3) {
                var hit3 = findRhNoteByPc(thirdPc);
                if (hit3 && !isBlockedByMelody(fourthTpc, false) && !isBlockedByMelody(tones.thirdTpc, false)) {
                    var start4Pitch = hit3.note.pitch + 1;
                    if (isCleanRhStep(start4Pitch, hit3.note.pitch, hit3.index)) {
                        return {
                            kind: "4-3",
                            repeatable: true,
                            staff: "rh",
                            movingIndex: hit3.index,
                            omitRhIndex: -1,
                            firstNote: { pitch: start4Pitch, tpc: fourthTpc },
                            secondNote: { pitch: hit3.note.pitch, tpc: tones.thirdTpc }
                        };
                    }
                }
            }

            var hitNat13 = findRhNoteByPc(nat13Pc);
            if (!explicit13 && isKindAllowed("13-b13") && hitNat13 && !isBlockedByMelody(nat13Tpc, false) && !isBlockedByMelody(flat13Tpc, false)) {
                var targetB13Pitch = hitNat13.note.pitch - 1;
                if (isCleanRhStep(hitNat13.note.pitch, targetB13Pitch, hitNat13.index)) {
                    return {
                        kind: "13-b13",
                        repeatable: false,
                        staff: "rh",
                        movingIndex: hitNat13.index,
                        omitRhIndex: -1,
                        firstNote: { pitch: hitNat13.note.pitch, tpc: nat13Tpc },
                        secondNote: { pitch: targetB13Pitch, tpc: flat13Tpc }
                    };
                }
            }

            if (isKindAllowed("4-3") && !chord.isSus && !block4To3 && (lhVoicing.tenorMidi % 12 === thirdPc) &&
                !isBlockedByMelody(fourthTpc, false) && !isBlockedByMelody(tones.thirdTpc, false)) {
                var lhStart4 = lhVoicing.tenorMidi + 1;
                if (isCleanLhTenorStep(lhStart4, lhVoicing.tenorMidi)) {
                    return {
                        kind: "4-3",
                        repeatable: true,
                        staff: "lh",
                        movingIndex: 1,
                        omitRhIndex: -1,
                        firstNote: { pitch: lhStart4, tpc: fourthTpc },
                        secondNote: { pitch: lhVoicing.tenorMidi, tpc: tones.thirdTpc }
                    };
                }
            }
        }

        var isMin7 = (chord.isMin && !chord.isHalfDim && !chord.isDim && !chord.isSixthChord);
        if (isMin7) {
            var min4Tpc = chord.rootTpc - 1;
            var min9Tpc = chord.rootTpc + 2;

            var hitMin3 = findRhNoteByPc(thirdPc);
            if (isKindAllowed("4-b3") && hitMin3 && !isBlockedByMelody(min4Tpc, false) && !isBlockedByMelody(tones.thirdTpc, false)) {
                var start4MinPitch = hitMin3.note.pitch + 2;
                if (isCleanRhStep(start4MinPitch, hitMin3.note.pitch, hitMin3.index)) {
                    return {
                        kind: "4-b3",
                        repeatable: true,
                        staff: "rh",
                        movingIndex: hitMin3.index,
                        omitRhIndex: -1,
                        firstNote: { pitch: start4MinPitch, tpc: min4Tpc },
                        secondNote: { pitch: hitMin3.note.pitch, tpc: tones.thirdTpc }
                    };
                }
            }
            var hit9 = findRhNoteByPc(nat9Pc);
            if (!chord.hasNat9 && isKindAllowed("9-1") && hit9 && !isBlockedByMelody(min9Tpc, false)) {
                var target1Pitch = hit9.note.pitch - 2;
                if (isCleanRhStep(hit9.note.pitch, target1Pitch, hit9.index)) {
                    return {
                        kind: "9-1",
                        repeatable: false,
                        staff: "rh",
                        movingIndex: hit9.index,
                        omitRhIndex: -1,
                        firstNote: { pitch: hit9.note.pitch, tpc: min9Tpc },
                        secondNote: { pitch: target1Pitch, tpc: tones.rootTpc }
                    };
                }
            }
            if (isKindAllowed("4-b3") && (lhVoicing.tenorMidi % 12 === thirdPc) &&
                !isBlockedByMelody(min4Tpc, false) && !isBlockedByMelody(tones.thirdTpc, false)) {
                var lhMinStart4 = lhVoicing.tenorMidi + 2;
                if (isCleanLhTenorStep(lhMinStart4, lhVoicing.tenorMidi)) {
                    return {
                        kind: "4-b3",
                        repeatable: true,
                        staff: "lh",
                        movingIndex: 1,
                        omitRhIndex: -1,
                        firstNote: { pitch: lhMinStart4, tpc: min4Tpc },
                        secondNote: { pitch: lhVoicing.tenorMidi, tpc: tones.thirdTpc }
                    };
                }
            }
        }

        return null;
    }

    function estimateNextBassMidi(nextChord, currentBassMidi) {
        var nextBassPc = tpcToPc(nextChord.bassTpc);
        var best = -1;
        var bestScore = -999999;
        for (var b = 36; b <= 58; b++) {
            if (b % 12 !== nextBassPc) continue;
            var sc = 0;
            if (b >= 41 && b <= 54) sc += 24;
            else if (b < 41) sc -= (41 - b) * 1.5;
            else sc -= 22 + (b - 55) * 14.0;

            var dist = Math.abs(b - currentBassMidi);
            if (dist <= 2) sc += 38;
            else if (dist <= 7) sc += 15;
            else if (dist >= 10) sc -= 18;

            if (sc > bestScore) {
                bestScore = sc;
                best = b;
            }
        }
        return best;
    }

    function planBeat3BassMotion(chord, tones, lhVoicing, nextChord, allowFifthOnBeat3, preferStepwiseNext) {
        var bassMidi = lhVoicing.bassMidi;
        var tenorMidi = lhVoicing.tenorMidi;

        var sameRootAsNext = (nextChord && (tpcToPc(chord.rootTpc) === tpcToPc(nextChord.rootTpc)));

        var alreadyHalfStepAboveNext = false;
        if (nextChord) {
            var nextBassPcCheck = tpcToPc(nextChord.bassTpc);
            if ((((bassMidi % 12) - nextBassPcCheck + 12) % 12) === 1) {
                alreadyHalfStepAboveNext = true;
            }
        }

        if (preferStepwiseNext && nextChord && !sameRootAsNext && !alreadyHalfStepAboveNext) {
            var nextBassMidi = estimateNextBassMidi(nextChord, bassMidi);
            if (nextBassMidi !== -1) {
                var chordToneList = [tones.rootTpc, tones.thirdTpc, tones.fifthTpc];
                if (tones.resolvedSeventhType !== null) {
                    chordToneList.push(tones.seventhTpc);
                }

                var stepCandidates = [];
                for (var ct = 0; ct < chordToneList.length; ct++) {
                    var ctTpc = chordToneList[ct];
                    var ctPc = tpcToPc(ctTpc);
                    if (ctPc === (bassMidi % 12)) continue;

                    for (var candPitch = 24; candPitch <= tenorMidi - 2; candPitch++) {
                        if (candPitch % 12 !== ctPc) continue;
                        if (candPitch === bassMidi) continue;
                        var stepToNext = Math.abs(candPitch - nextBassMidi);
                        var leapFromCurr = Math.abs(candPitch - bassMidi);
                        if (stepToNext >= 1 && stepToNext <= 2 && leapFromCurr <= 7) {
                            stepCandidates.push({
                                pitch: candPitch,
                                tpc: ctTpc,
                                score: (stepToNext === 1 ? 20 : 10) - leapFromCurr
                            });
                        }
                    }
                }

                if (stepCandidates.length > 0) {
                    stepCandidates.sort(function(a, b) { return b.score - a.score; });
                    return {
                        kind: "bass-step",
                        staff: "lh",
                        movingIndex: 0,
                        omitRhIndex: -1,
                        firstNote: { pitch: bassMidi, tpc: lhVoicing.bassTpc },
                        secondNote: { pitch: stepCandidates[0].pitch, tpc: stepCandidates[0].tpc }
                    };
                }
            }
        }

        if (allowFifthOnBeat3 || sameRootAsNext) {
            var fifthPc = tpcToPc(tones.fifthTpc);
            if (fifthPc !== (bassMidi % 12)) {
                var fifthBelow = placePcAtOrBelow(fifthPc, bassMidi - 1);
                var fifthAbove = placePcAtOrAbove(fifthPc, bassMidi + 1);
                var chosenFifth = -1;
                if (fifthBelow >= 24 && fifthBelow <= tenorMidi - 2) {
                    chosenFifth = fifthBelow;
                } else if (fifthAbove <= tenorMidi - 2) {
                    chosenFifth = fifthAbove;
                }
                if (chosenFifth !== -1) {
                    return {
                        kind: "bass-fifth",
                        staff: "lh",
                        movingIndex: 0,
                        omitRhIndex: -1,
                        firstNote: { pitch: bassMidi, tpc: lhVoicing.bassTpc },
                        secondNote: { pitch: chosenFifth, tpc: tones.fifthTpc }
                    };
                }
            }
        }

        if ((bassMidi - 12) >= 24) {
            return {
                kind: "bass-octave",
                staff: "lh",
                movingIndex: 0,
                omitRhIndex: -1,
                firstNote: { pitch: bassMidi, tpc: lhVoicing.bassTpc },
                secondNote: { pitch: bassMidi - 12, tpc: lhVoicing.bassTpc }
            };
        }

        return null;
    }

    // --- Direct Segment-Walk Readers ---

    function measureHasSectionBreak(measure) {
        if (!measure) return false;
        if (measure.el) {
            for (var e = 0; e < measure.el.length; e++) {
                var mel = measure.el[e];
                if (mel && mel.type === Element.LAYOUT_BREAK && mel.layoutBreakType === LayoutBreak.SECTION) {
                    return true;
                }
            }
        }
        return false;
    }

    function scanScoreData(score) {
        var events = [];
        var melodyNotes = [];
        var measures = [];

        var initCursor = score.newCursor();
        initCursor.staffIdx = 0;
        initCursor.rewind(Cursor.SCORE_START);
        var currentKeySig = initCursor.keySignature;
        var currentNum = 4;
        var currentDen = 4;

        var mList = [];
        var m = score.firstMeasure;
        while (m) {
            if (m.firstSegment) mList.push(m);
            m = m.nextMeasure;
        }

        var scoreEndTick = 0;
        var lastMelodyStartTick = 0;
        var lastMelodyEndTick = 0;

        for (var idx = 0; idx < mList.length; idx++) {
            var currM = mList[idx];
            var mStart = currM.firstSegment.tick;
            var mEnd = 0;

            if (idx + 1 < mList.length) {
                mEnd = mList[idx + 1].firstSegment.tick;
            } else {
                var s = currM.firstSegment;
                var maxEnd = mStart;
                while (s) {
                    if (s.segmentType & Segment.ChordRest) {
                        var el = s.elementAt(0);
                        var dur = (el && el.duration) ? el.duration.ticks : 0;
                        if (s.tick + dur > maxEnd) maxEnd = s.tick + dur;
                    }
                    var nextS = s.nextInMeasure;
                    if (!nextS || nextS.tick < s.tick) break;
                    s = nextS;
                }
                mEnd = maxEnd > mStart ? maxEnd : mStart + 1920;
            }

            var hasSectionEnd = measureHasSectionBreak(currM);

            var seg = currM.firstSegment;
            while (seg) {
                if (seg.segmentType & Segment.TimeSig) {
                    var tsEl = seg.elementAt(0);
                    if (tsEl && tsEl.timesig) {
                        currentNum = tsEl.timesig.numerator;
                        currentDen = tsEl.timesig.denominator;
                    }
                }
                if (seg.segmentType & Segment.KeySig) {
                    var ksEl = seg.elementAt(0);
                    if (ksEl && ksEl.key !== undefined) {
                        currentKeySig = ksEl.key;
                    }
                }

                if (seg.segmentType & Segment.ChordRest) {
                    if (seg.annotations) {
                        for (var a = 0; a < seg.annotations.length; a++) {
                            var ann = seg.annotations[a];
                            if (ann.type === Element.HARMONY) {
                                var parsed = parseChordSymbol(ann.text);
                                if (parsed) {
                                    events.push({
                                        tick: seg.tick,
                                        chord: parsed,
                                        keySig: currentKeySig,
                                        harmonyEl: ann
                                    });
                                }
                            }
                        }
                    }

                    var melEl = seg.elementAt(0);
                    if (melEl && melEl.type === Element.CHORD && melEl.notes) {
                        var noteStart = seg.tick;
                        var noteEnd = noteStart + melEl.duration.ticks;
                        if (noteStart >= lastMelodyStartTick) {
                            lastMelodyStartTick = noteStart;
                        }
                        if (noteEnd > lastMelodyEndTick) {
                            lastMelodyEndTick = noteEnd;
                        }
                        for (var n = 0; n < melEl.notes.length; n++) {
                            var noteItem = melEl.notes[n];
                            var isTiedBack = (noteItem.tieBack !== null && noteItem.tieBack !== undefined);
                            var chainStart = noteStart;
                            if (isTiedBack) {
                                for (var prevIdx = melodyNotes.length - 1; prevIdx >= 0; prevIdx--) {
                                    var prevMn = melodyNotes[prevIdx];
                                    if (prevMn.pitch === noteItem.pitch && prevMn.endTick === noteStart) {
                                        chainStart = prevMn.chainStartTick;
                                        break;
                                    }
                                }
                            }
                            melodyNotes.push({
                                startTick: noteStart,
                                chainStartTick: chainStart,
                                endTick: noteEnd,
                                pitch: noteItem.pitch
                            });
                        }
                    }
                }

                var nxt = seg.nextInMeasure;
                if (!nxt || nxt.tick < seg.tick) break;
                seg = nxt;
            }

            measures.push({
                startTick: mStart,
                endTick: mEnd,
                timeSigNum: currentNum,
                timeSigDen: currentDen,
                hasSectionBreak: hasSectionEnd
            });
            if (mEnd > scoreEndTick) scoreEndTick = mEnd;
        }

        var effectiveEndTick = (lastMelodyEndTick > 0) ? lastMelodyEndTick : scoreEndTick;
        var filteredEvents = filterOptionalEndTurnarounds(events, measures, effectiveEndTick);

        return {
            events: filteredEvents,
            melodyNotes: melodyNotes,
            measures: measures,
            scoreEndTick: effectiveEndTick,
            lastMelodyStartTick: lastMelodyStartTick,
            lastMelodyEndTick: effectiveEndTick
        };
    }

    function analyzeMelodyFromCache(melodyNotes, startTick, endTick) {
        var pcDurations = {};
        var firstHalfPcDurations = {};
        var pcLowestMidi = {};
        var staleTiedPcs = {};
        var overallLowestMidi = 127;
        var firstHalfLowestMidi = 127;
        var highestMidi = 0;
        var totalWindowTicks = Math.max(1, endTick - startTick);
        var midTick = startTick + Math.floor(totalWindowTicks / 2);
        var attacksAfterStart = 0;

        for (var i = 0; i < melodyNotes.length; i++) {
            var mn = melodyNotes[i];
            if (mn.endTick <= startTick) continue;
            if (mn.startTick >= endTick) break;

            var overlap = Math.min(endTick, mn.endTick) - Math.max(startTick, mn.startTick);
            if (overlap > 0) {
                if (mn.pitch < overallLowestMidi) overallLowestMidi = mn.pitch;
                if (mn.pitch > highestMidi) highestMidi = mn.pitch;
                if (mn.startTick > startTick) attacksAfterStart++;

                var pc = mn.pitch % 12;
                pcDurations[pc] = (pcDurations[pc] || 0) + overlap;

                if (mn.startTick < midTick) {
                    if (mn.pitch < firstHalfLowestMidi) {
                        firstHalfLowestMidi = mn.pitch;
                    }
                    var firstHalfOverlap = Math.min(midTick, mn.endTick) - Math.max(startTick, mn.startTick);
                    if (firstHalfOverlap > 0) {
                        firstHalfPcDurations[pc] = (firstHalfPcDurations[pc] || 0) + firstHalfOverlap;
                    }
                }

                if (pcLowestMidi[pc] === undefined || mn.pitch < pcLowestMidi[pc]) {
                    pcLowestMidi[pc] = mn.pitch;
                }

                var trueOnset = (mn.chainStartTick !== undefined) ? mn.chainStartTick : mn.startTick;
                if (trueOnset <= startTick - 1440 && mn.endTick > startTick) {
                    staleTiedPcs[pc] = true;
                }
            }
        }

        var effectiveLowestMidi = (firstHalfLowestMidi < 127) ? firstHalfLowestMidi : overallLowestMidi;

        return {
            pcDurations: pcDurations,
            firstHalfPcDurations: firstHalfPcDurations,
            pcLowestMidi: pcLowestMidi,
            staleTiedPcs: staleTiedPcs,
            totalTicks: totalWindowTicks,
            lowestMidi: effectiveLowestMidi,
            overallLowestMidi: overallLowestMidi,
            highestMidi: (highestMidi > 0) ? highestMidi : 127,
            isMelodyStatic: (attacksAfterStart === 0)
        };
    }

    function splitByMeasures(measures, startTick, endTick) {
        var chunks = [];
        for (var i = 0; i < measures.length; i++) {
            var m = measures[i];
            if (m.endTick <= startTick) continue;
            if (m.startTick >= endTick) break;

            var cStart = Math.max(startTick, m.startTick);
            var cEnd = Math.min(endTick, m.endTick);
            if (cEnd > cStart) {
                chunks.push({
                    startTick: cStart,
                    durationTicks: cEnd - cStart,
                    measureStartTick: m.startTick,
                    measureEndTick: m.endTick,
                    timeSigNum: m.timeSigNum,
                    timeSigDen: m.timeSigDen,
                    hasSectionBreak: m.hasSectionBreak
                });
            }
        }
        return chunks;
    }

    function syncKeySignatures(score, targetStaves) {
        var ksCursor = score.newCursor();
        ksCursor.voice = 0;

        var m = score.firstMeasure;
        while (m) {
            var seg = m.firstSegment;
            while (seg) {
                if (seg.segmentType & Segment.KeySig) {
                    var srcKs = seg.elementAt(0);
                    if (srcKs && srcKs.type === Element.KEYSIG) {
                        for (var s = 0; s < targetStaves.length; s++) {
                            var sIdx = targetStaves[s];
                            var dstKs = seg.elementAt(sIdx * 4);
                            if (dstKs && dstKs.type === Element.KEYSIG) {
                                removeElement(dstKs);
                            }
                            var cloned = srcKs.clone();
                            cloned.track = sIdx * 4;
                            ksCursor.staffIdx = sIdx;
                            ksCursor.voice = 0;
                            ksCursor.rewindToTick(seg.tick);
                            ksCursor.add(cloned);
                        }
                    }
                }
                var nxt = seg.nextInMeasure;
                if (!nxt || nxt.tick < seg.tick) break;
                seg = nxt;
            }
            m = m.nextMeasure;
        }
    }

    function seekCursorTrack(cursor, staffIdx, voice, startTick, measureStartTick) {
        cursor.staffIdx = staffIdx;
        cursor.voice = voice;
        cursor.rewindToTick(startTick);

        if (cursor.segment === null && voice > 0 && measureStartTick !== undefined) {
            cursor.voice = 0;
            cursor.rewindToTick(measureStartTick);
            cursor.voice = voice;
            if (startTick > measureStartTick && cursor.segment !== null) {
                cursor.setDuration(startTick - measureStartTick, 1920);
                cursor.addRest();
                cursor.rewindToTick(startTick);
            }
        }
    }

    function writeSpelledChord(cursor, staffIdx, voice, startTick, durationTicks, notesSpec, measureStartTick) {
        var sorted = notesSpec.slice().sort(function(a, b) { return a.pitch - b.pitch; });

        seekCursorTrack(cursor, staffIdx, voice, startTick, measureStartTick);
        if (cursor.segment === null) return;

        cursor.setDuration(durationTicks, 1920);
        for (var i = 0; i < sorted.length; i++) {
            if (i > 0) {
                seekCursorTrack(cursor, staffIdx, voice, startTick, measureStartTick);
            }
            cursor.addNote(sorted[i].pitch, i > 0);
        }

        seekCursorTrack(cursor, staffIdx, voice, startTick, measureStartTick);
        var chordEl = cursor.element;
        if (chordEl && chordEl.type === Element.CHORD && chordEl.notes) {
            for (var n = 0; n < chordEl.notes.length; n++) {
                var noteObj = chordEl.notes[n];
                for (var j = 0; j < sorted.length; j++) {
                    if (noteObj.pitch === sorted[j].pitch) {
                        noteObj.tpc1 = sorted[j].tpc;
                        noteObj.tpc2 = sorted[j].tpc;
                    }
                }
            }
        }
    }

    // Write a single sequential moving voice in targetVoice starting from measureStartTick,
    // advancing naturally via cursor.addNote() so splitTick never falls back onto Voice 0!
    function writeSequentialMotionVoice(cursor, staffIdx, targetVoice, mStart, cStart, firstNote, d1, secondNote, d2) {
        cursor.staffIdx = staffIdx;
        cursor.voice = 0;
        cursor.rewindToTick(mStart);
        cursor.voice = targetVoice;
        if (cursor.segment === null) return;

        if (cStart > mStart) {
            cursor.setDuration(cStart - mStart, 1920);
            cursor.addRest();
        }

        // Write firstNote (duration d1)
        cursor.setDuration(d1, 1920);
        cursor.addNote(firstNote.pitch, false);
        // Spell firstNote via a fresh lookup on targetVoice at cStart
        cursor.staffIdx = staffIdx;
        cursor.voice = targetVoice;
        cursor.rewindToTick(cStart);
        var el1 = cursor.element;
        if (el1 && el1.type === Element.CHORD && el1.notes && el1.notes.length > 0) {
            el1.notes[0].tpc1 = firstNote.tpc;
            el1.notes[0].tpc2 = firstNote.tpc;
        }
        // Advance cursor to splitTick (cStart + d1)
        cursor.next();

        // Write secondNote (duration d2) directly at the advanced cursor position
        cursor.setDuration(d2, 1920);
        cursor.addNote(secondNote.pitch, false);
        cursor.staffIdx = staffIdx;
        cursor.voice = targetVoice;
        cursor.rewindToTick(cStart + d1);
        var el2 = cursor.element;
        if (el2 && el2.type === Element.CHORD && el2.notes && el2.notes.length > 0) {
            el2.notes[0].tpc1 = secondNote.tpc;
            el2.notes[0].tpc2 = secondNote.tpc;
        }
    }

    function writeStaffChunkWithMotion(cursor, staffIdx, chunk, allNotesSpec, movingIndex, firstNote, secondNote, splitTick) {
        var stationaryNotes = [];
        for (var i = 0; i < allNotesSpec.length; i++) {
            if (i !== movingIndex) {
                stationaryNotes.push(allNotesSpec[i]);
            }
        }

        var cStart = chunk.startTick;
        var cEnd = chunk.startTick + chunk.durationTicks;
        var mStart = chunk.measureStartTick;
        var targetVoice = (stationaryNotes.length > 0) ? 1 : 0;

        if (stationaryNotes.length > 0) {
            writeSpelledChord(cursor, staffIdx, 0, cStart, chunk.durationTicks, stationaryNotes, mStart);
        }

        if (cEnd <= splitTick) {
            writeSpelledChord(cursor, staffIdx, targetVoice, cStart, chunk.durationTicks, [firstNote], mStart);
        } else if (cStart >= splitTick) {
            writeSpelledChord(cursor, staffIdx, targetVoice, cStart, chunk.durationTicks, [secondNote], mStart);
        } else {
            var d1 = splitTick - cStart;
            var d2 = cEnd - splitTick;
            writeSequentialMotionVoice(cursor, staffIdx, targetVoice, mStart, cStart, firstNote, d1, secondNote, d2);
        }
    }

    onRun: {
        if (!curScore) {
            quit();
            return;
        }

        curScore.startCmd();

        // 1. Ensure a 2-staff piano part exists
        var pianoPart = null;
        for (var p = 1; p < curScore.parts.length; p++) {
            if (curScore.parts[p].staves.length === 2) {
                pianoPart = curScore.parts[p];
                break;
            }
        }

        if (!pianoPart) {
            curScore.appendPart("piano");
            pianoPart = curScore.parts[curScore.parts.length - 1];
            if (pianoPart.staves.length < 2) {
                curScore.appendStaff(pianoPart);
            }
        }

        if (curScore.nstaves < 3) {
            curScore.endCmd();
            quit();
            return;
        }

        var rhStaffIdx = 1;
        var lhStaffIdx = 2;

        // 2. Single segment-walk pass to read chords, melody, and measure boundaries
        var scoreData = scanScoreData(curScore);
        var events = scoreData.events;
        if (events.length === 0) {
            curScore.endCmd();
            quit();
            return;
        }

        annotateChromaticDomChains(events);

        // 3. Configure barlines, brace, bass clef, and key signatures
        if (curScore.staves && curScore.staves.length >= 3) {
            curScore.staves[0].barLineSpan = 1;
            curScore.staves[1].barLineSpan = 2;
            curScore.staves[2].barLineSpan = 0;

            if (typeof curScore.staves[1].addBracket === "function") {
                curScore.staves[1].addBracket(0, BracketType.BRACE, 2);
            }
        }

        var hdrSeg = curScore.firstMeasure ? curScore.firstMeasure.firstSegment : null;
        while (hdrSeg) {
            if (hdrSeg.segmentType & Segment.HeaderClef) {
                var hdrClef = hdrSeg.elementAt(lhStaffIdx * 4);
                if (hdrClef && hdrClef.type === Element.CLEF) {
                    hdrClef.clefType = ClefType.F;
                }
                break;
            }
            var hNxt = hdrSeg.nextInMeasure;
            if (!hNxt || hNxt.tick < hdrSeg.tick) break;
            hdrSeg = hNxt;
        }

        syncKeySignatures(curScore, [rhStaffIdx, lhStaffIdx]);

        var writeCursor = curScore.newCursor();

        var prevChord = null;
        var prevBassMidi = -1;
        var prevLhTenorMidi = -1;
        var prevLhRole = null;
        var prevRhCenterMidi = -1;
        var prevRhColorAbove = null;

        for (var i = 0; i < events.length; i++) {
            var ev = events[i];

            if (ev.harmonyEl && ev.harmonyEl.play !== undefined) {
                ev.harmonyEl.play = false;
            }

            var isLastEvent = (i === events.length - 1);
            var nextChord = !isLastEvent ? events[i + 1].chord : null;
            var startTick = ev.tick;
            var endTick = !isLastEvent ? events[i + 1].tick : scoreData.scoreEndTick;
            var totalDuration = endTick - startTick;
            if (totalDuration <= 0) continue;

            var chainFlags = {
                isTritoneSub: ev.isTritoneSub,
                keepFifthFromPrevSharp11: ev.keepFifthFromPrevSharp11
            };

            var tones = getChordToneTpcs(ev.chord, ev.keySig);
            var chunks = splitByMeasures(scoreData.measures, startTick, endTick);
            if (chunks.length === 0) continue;

            var is34 = (chunks[0].timeSigNum === 3 && chunks[0].timeSigDen === 4);
            var numBars = chunks.length;

            var endsAtSectionBreak = chunks[chunks.length - 1].hasSectionBreak;
            var isSectionEndChord = isLastEvent || endsAtSectionBreak;

            if (isSectionEndChord) {
                var secMel = analyzeMelodyFromCache(scoreData.melodyNotes, startTick, endTick);
                var secVoicing = computeBarVoicing(
                    ev.chord, tones, ev.keySig, nextChord, prevChord,
                    prevBassMidi, prevLhTenorMidi, prevLhRole, prevRhCenterMidi, prevRhColorAbove,
                    secMel, null, null, chainFlags
                );
                var sLh = secVoicing.lhVoicing;
                var sRhSpec = secVoicing.rhNotesSpec.slice();
                var sLhSpec = [
                    { pitch: sLh.bassMidi, tpc: sLh.bassTpc },
                    { pitch: sLh.tenorMidi, tpc: sLh.tenorTpc }
                ];
                var rootBaseMidi = placePcAtOrBelow(tpcToPc(tones.rootTpc), sLh.bassMidi);
                var lowRootNote = ((rootBaseMidi - 12) >= 24)
                    ? { pitch: rootBaseMidi - 12, tpc: tones.rootTpc }
                    : { pitch: rootBaseMidi, tpc: tones.rootTpc };

                var lastMelAttackInWindow = startTick;
                for (var mnIdx = 0; mnIdx < scoreData.melodyNotes.length; mnIdx++) {
                    var mnItem = scoreData.melodyNotes[mnIdx];
                    if (mnItem.startTick >= startTick && mnItem.startTick < endTick) {
                        if (mnItem.startTick > lastMelAttackInWindow) lastMelAttackInWindow = mnItem.startTick;
                    }
                }

                for (var fc = 0; fc < chunks.length; fc++) {
                    var fChunk = chunks[fc];
                    var fcStart = fChunk.startTick;

                    if (fc === 0) {
                        var beat3Tick = fcStart + 960;
                        if (lastMelAttackInWindow <= fcStart && fChunk.durationTicks >= 1920 && lowRootNote.pitch < sLh.bassMidi) {
                            writeStaffChunkWithMotion(
                                writeCursor, lhStaffIdx, fChunk, sLhSpec,
                                0, { pitch: sLh.bassMidi, tpc: sLh.bassTpc }, lowRootNote, beat3Tick
                            );
                        } else {
                            writeSpelledChord(writeCursor, lhStaffIdx, 0, fcStart, fChunk.durationTicks, sLhSpec, fChunk.measureStartTick);
                        }

                        if (sRhSpec.length > 0) {
                            writeSpelledChord(writeCursor, rhStaffIdx, 0, fcStart, fChunk.durationTicks, sRhSpec, fChunk.measureStartTick);
                        } else {
                            seekCursorTrack(writeCursor, rhStaffIdx, 0, fcStart, fChunk.measureStartTick);
                            if (writeCursor.segment !== null) {
                                writeCursor.setDuration(fChunk.durationTicks, 1920);
                                writeCursor.addRest();
                            }
                        }
                    } else {
                        writeSpelledChord(writeCursor, lhStaffIdx, 0, fcStart, fChunk.durationTicks, [lowRootNote], fChunk.measureStartTick);
                        seekCursorTrack(writeCursor, rhStaffIdx, 0, fcStart, fChunk.measureStartTick);
                        if (writeCursor.segment !== null) {
                            writeCursor.setDuration(fChunk.durationTicks, 1920);
                            writeCursor.addRest();
                        }
                    }
                }

                prevChord = ev.chord;
                prevBassMidi = lowRootNote.pitch;
                prevLhTenorMidi = sLh.tenorMidi;
                prevLhRole = sLh.role;
                prevRhColorAbove = secVoicing.currentColorAbove;
                if (sRhSpec.length > 0) {
                    var sumSec = 0;
                    for (var sr = 0; sr < sRhSpec.length; sr++) sumSec += sRhSpec[sr].pitch;
                    prevRhCenterMidi = sumSec / sRhSpec.length;
                }
                continue;
            }

            // --- Case 1: Two-measure 3/4 chord ---
            if (is34 && numBars === 2 &&
                chunks[0].startTick === chunks[0].measureStartTick &&
                chunks[1].durationTicks === (chunks[1].measureEndTick - chunks[1].measureStartTick)) {

                var bar1Mel = analyzeMelodyFromCache(scoreData.melodyNotes, chunks[0].startTick, chunks[0].startTick + chunks[0].durationTicks);
                var bar2Mel = analyzeMelodyFromCache(scoreData.melodyNotes, chunks[1].startTick, chunks[1].startTick + chunks[1].durationTicks);
                var combinedMel = analyzeMelodyFromCache(scoreData.melodyNotes, startTick, endTick);

                var base34 = computeBarVoicing(
                    ev.chord, tones, ev.keySig, nextChord, prevChord,
                    prevBassMidi, prevLhTenorMidi, prevLhRole, prevRhCenterMidi, prevRhColorAbove,
                    combinedMel, null, null, chainFlags
                );

                var lhBar1 = [
                    { pitch: base34.lhVoicing.bassMidi, tpc: base34.lhVoicing.bassTpc },
                    { pitch: base34.lhVoicing.tenorMidi, tpc: base34.lhVoicing.tenorTpc }
                ];
                var lhBar2 = [
                    { pitch: base34.lhVoicing.bassMidi, tpc: base34.lhVoicing.bassTpc },
                    { pitch: base34.lhVoicing.tenorMidi, tpc: base34.lhVoicing.tenorTpc }
                ];
                var rhBar1 = base34.rhNotesSpec.slice();
                var rhBar2 = base34.rhNotesSpec.slice();

                var motion34 = planInnerOrUpperMotion(ev.chord, tones, base34.lhVoicing, base34.rhNotesSpec, base34.rhCeiling, combinedMel, null, chainFlags, bar2Mel);
                if (motion34) {
                    if (motion34.omitRhIndex !== undefined && motion34.omitRhIndex >= 0) {
                        var omIdx = motion34.omitRhIndex;
                        rhBar1.splice(omIdx, 1);
                        rhBar2.splice(omIdx, 1);
                        if (motion34.staff === "rh" && motion34.movingIndex > omIdx) {
                            motion34.movingIndex -= 1;
                        }
                    }

                    if (motion34.staff === "rh") {
                        if (motion34.firstNote.pitch <= bar1Mel.overallLowestMidi - 1 &&
                            motion34.secondNote.pitch <= bar2Mel.overallLowestMidi - 1) {
                            rhBar1[motion34.movingIndex] = motion34.firstNote;
                            rhBar2[motion34.movingIndex] = motion34.secondNote;
                        }
                    } else if (motion34.staff === "lh") {
                        if (motion34.firstNote.pitch <= bar1Mel.overallLowestMidi - 1 &&
                            motion34.secondNote.pitch <= bar2Mel.overallLowestMidi - 1) {
                            lhBar1[motion34.movingIndex] = motion34.firstNote;
                            lhBar2[motion34.movingIndex] = motion34.secondNote;
                        }
                    }
                }

                writeSpelledChord(writeCursor, lhStaffIdx, 0, chunks[0].startTick, chunks[0].durationTicks, lhBar1, chunks[0].measureStartTick);
                if (rhBar1.length > 0) {
                    writeSpelledChord(writeCursor, rhStaffIdx, 0, chunks[0].startTick, chunks[0].durationTicks, rhBar1, chunks[0].measureStartTick);
                } else {
                    seekCursorTrack(writeCursor, rhStaffIdx, 0, chunks[0].startTick, chunks[0].measureStartTick);
                    if (writeCursor.segment !== null) { writeCursor.setDuration(chunks[0].durationTicks, 1920); writeCursor.addRest(); }
                }

                writeSpelledChord(writeCursor, lhStaffIdx, 0, chunks[1].startTick, chunks[1].durationTicks, lhBar2, chunks[1].measureStartTick);
                if (rhBar2.length > 0) {
                    writeSpelledChord(writeCursor, rhStaffIdx, 0, chunks[1].startTick, chunks[1].durationTicks, rhBar2, chunks[1].measureStartTick);
                } else {
                    seekCursorTrack(writeCursor, rhStaffIdx, 0, chunks[1].startTick, chunks[1].measureStartTick);
                    if (writeCursor.segment !== null) { writeCursor.setDuration(chunks[1].durationTicks, 1920); writeCursor.addRest(); }
                }

                prevChord = ev.chord;
                prevBassMidi = lhBar2[0].pitch;
                prevLhTenorMidi = lhBar2[1].pitch;
                prevLhRole = base34.lhVoicing.role;
                prevRhColorAbove = base34.currentColorAbove;
                if (rhBar2.length > 0) {
                    var sum34 = 0;
                    for (var s34 = 0; s34 < rhBar2.length; s34++) sum34 += rhBar2[s34].pitch;
                    prevRhCenterMidi = sum34 / rhBar2.length;
                }
                continue;
            }

            // --- Case 2: Standard single-bar or multi-bar measure-by-measure realization ---
            var isMaj7Family = (tones.resolvedSeventhType === "maj7" || tones.resolvedSeventhType === "min6" || ev.chord.isSixthChord);
            var isDom7 = (tones.resolvedSeventhType === "dom7" && !ev.chord.isMin && !ev.chord.isDim);

            var twoBarDom9ToFlat9 = (numBars === 2 && isDom7 && !is34 && !ev.isTritoneSub &&
                (ev.chord.hasFlat9 || ev.chord.isAlt || (nextChord && ((tpcToPc(nextChord.rootTpc) - tpcToPc(ev.chord.rootTpc) + 12) % 12 === 5))));

            var localPrevChord = prevChord;
            var localPrevBass = prevBassMidi;
            var localPrevTenor = prevLhTenorMidi;
            var localPrevRole = prevLhRole;
            var localPrevRhCenter = prevRhCenterMidi;
            var localPrevColorAbove = prevRhColorAbove;

            for (var c = 0; c < chunks.length; c++) {
                var chunk = chunks[c];
                var cStart = chunk.startTick;
                var cEnd = chunk.startTick + chunk.durationTicks;
                var isFullMeasure = (cStart === chunk.measureStartTick && cEnd === chunk.measureEndTick);
                var isLastBarOfChord = (c === chunks.length - 1);

                var barMelodyInfo = analyzeMelodyFromCache(scoreData.melodyNotes, cStart, cEnd);

                var barExtMode = null;
                if (twoBarDom9ToFlat9) {
                    barExtMode = (c === 0) ? "nat9" : "flat9";
                }

                var altRole = null;
                if (c > 0 && !twoBarDom9ToFlat9 && localPrevRole !== null) {
                    altRole = (localPrevRole === "third") ? "seventh" : "third";
                }

                var barVoicing = computeBarVoicing(
                    ev.chord, tones, ev.keySig, nextChord, localPrevChord,
                    localPrevBass, localPrevTenor, localPrevRole, localPrevRhCenter, localPrevColorAbove,
                    barMelodyInfo, barExtMode, altRole, chainFlags
                );

                var lhVoicing = barVoicing.lhVoicing;
                var rhNotesSpec = barVoicing.rhNotesSpec.slice();
                var rhCeiling = barVoicing.rhCeiling;
                var lhNotesSpec = [
                    { pitch: lhVoicing.bassMidi, tpc: lhVoicing.bassTpc },
                    { pitch: lhVoicing.tenorMidi, tpc: lhVoicing.tenorTpc }
                ];

                var barMotion = null;
                var splitTick = cStart + 960;
                var secondHalfMelodyInfo = (cEnd > splitTick)
                    ? analyzeMelodyFromCache(scoreData.melodyNotes, splitTick, cEnd)
                    : barMelodyInfo;

                if (isFullMeasure) {
                    if (is34) {
                        if (barMelodyInfo.isMelodyStatic && chunk.durationTicks >= 1440) {
                            var inner34 = planInnerOrUpperMotion(ev.chord, tones, lhVoicing, rhNotesSpec, rhCeiling, barMelodyInfo, null, chainFlags, secondHalfMelodyInfo);
                            barMotion = inner34 ? inner34 : planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, numBars > 1, isLastBarOfChord);
                        }
                    } else if (chunk.durationTicks >= 1920) {
                        if (twoBarDom9ToFlat9) {
                            barMotion = planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, true, isLastBarOfChord);
                        } else if (numBars > 2) {
                            if (isMaj7Family) {
                                var allowedMajKinds = (c === 0) ? ["7-6"] : ((c === 1) ? ["6-5", "7-6"] : ["7-6"]);
                                var multiMajInner = (c < 3) ? planInnerOrUpperMotion(ev.chord, tones, lhVoicing, rhNotesSpec, rhCeiling, barMelodyInfo, allowedMajKinds, chainFlags, secondHalfMelodyInfo) : null;
                                barMotion = multiMajInner ? multiMajInner : planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, true, isLastBarOfChord);
                            } else if (isDom7) {
                                var allowedDomKinds = isLastBarOfChord ? ["9-b9", "4-3"] : ["4-3"];
                                var multiDomInner = planInnerOrUpperMotion(ev.chord, tones, lhVoicing, rhNotesSpec, rhCeiling, barMelodyInfo, allowedDomKinds, chainFlags, secondHalfMelodyInfo);
                                barMotion = multiDomInner ? multiDomInner : planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, true, isLastBarOfChord);
                            } else {
                                var multiOtherInner = planInnerOrUpperMotion(ev.chord, tones, lhVoicing, rhNotesSpec, rhCeiling, barMelodyInfo, null, chainFlags, secondHalfMelodyInfo);
                                barMotion = multiOtherInner ? multiOtherInner : planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, true, isLastBarOfChord);
                            }
                        } else if (numBars === 2) {
                            if (c === 0) {
                                var bar1Inner = planInnerOrUpperMotion(ev.chord, tones, lhVoicing, rhNotesSpec, rhCeiling, barMelodyInfo, null, chainFlags, secondHalfMelodyInfo);
                                barMotion = bar1Inner ? bar1Inner : planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, true, false);
                            } else {
                                var bar2Inner = planInnerOrUpperMotion(ev.chord, tones, lhVoicing, rhNotesSpec, rhCeiling, barMelodyInfo, ["4-3", "7-6", "6-5", "4-b3"], chainFlags, secondHalfMelodyInfo);
                                barMotion = bar2Inner ? bar2Inner : planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, true, true);
                            }
                        } else {
                            var singleInner = planInnerOrUpperMotion(ev.chord, tones, lhVoicing, rhNotesSpec, rhCeiling, barMelodyInfo, null, chainFlags, secondHalfMelodyInfo);
                            barMotion = singleInner ? singleInner : planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, false, true);
                        }
                    }
                } else if (!is34 && chunk.durationTicks >= 1920) {
                    var offBarInner = planInnerOrUpperMotion(ev.chord, tones, lhVoicing, rhNotesSpec, rhCeiling, barMelodyInfo, null, chainFlags, secondHalfMelodyInfo);
                    barMotion = offBarInner ? offBarInner : planBeat3BassMotion(ev.chord, tones, lhVoicing, nextChord, numBars > 1, isLastBarOfChord);
                }

                if (barMotion && barMotion.omitRhIndex !== undefined && barMotion.omitRhIndex >= 0) {
                    var omIdx2 = barMotion.omitRhIndex;
                    rhNotesSpec.splice(omIdx2, 1);
                    if (barMotion.staff === "rh" && barMotion.movingIndex > omIdx2) {
                        barMotion.movingIndex -= 1;
                    }
                }

                if (barMotion && barMotion.staff === "lh") {
                    writeStaffChunkWithMotion(
                        writeCursor, lhStaffIdx, chunk, lhNotesSpec,
                        barMotion.movingIndex, barMotion.firstNote, barMotion.secondNote, splitTick
                    );
                } else {
                    writeSpelledChord(writeCursor, lhStaffIdx, 0, cStart, chunk.durationTicks, lhNotesSpec, chunk.measureStartTick);
                }

                if (barMotion && barMotion.staff === "rh") {
                    writeStaffChunkWithMotion(
                        writeCursor, rhStaffIdx, chunk, rhNotesSpec,
                        barMotion.movingIndex, barMotion.firstNote, barMotion.secondNote, splitTick
                    );
                } else if (rhNotesSpec.length > 0) {
                    writeSpelledChord(writeCursor, rhStaffIdx, 0, cStart, chunk.durationTicks, rhNotesSpec, chunk.measureStartTick);
                } else {
                    seekCursorTrack(writeCursor, rhStaffIdx, 0, cStart, chunk.measureStartTick);
                    if (writeCursor.segment !== null) {
                        writeCursor.setDuration(chunk.durationTicks, 1920);
                        writeCursor.addRest();
                    }
                }

                localPrevChord = ev.chord;
                localPrevBass = (barMotion && barMotion.staff === "lh" && barMotion.movingIndex === 0)
                    ? barMotion.secondNote.pitch : lhVoicing.bassMidi;
                localPrevTenor = (barMotion && barMotion.staff === "lh" && barMotion.movingIndex === 1)
                    ? barMotion.secondNote.pitch : lhVoicing.tenorMidi;
                localPrevRole = lhVoicing.role;
                localPrevColorAbove = barVoicing.currentColorAbove;

                if (rhNotesSpec.length > 0) {
                    var sumBarRh = 0;
                    for (var br = 0; br < rhNotesSpec.length; br++) {
                        var pBarEnd = (barMotion && barMotion.staff === "rh" && barMotion.movingIndex === br)
                            ? barMotion.secondNote.pitch : rhNotesSpec[br].pitch;
                        sumBarRh += pBarEnd;
                    }
                    localPrevRhCenter = sumBarRh / rhNotesSpec.length;
                }
            }

            prevChord = localPrevChord;
            prevBassMidi = localPrevBass;
            prevLhTenorMidi = localPrevTenor;
            prevLhRole = localPrevRole;
            prevRhCenterMidi = localPrevRhCenter;
            prevRhColorAbove = localPrevColorAbove;
        }

        curScore.endCmd();
        quit();
    }
}