//
//  PhaseGuideContent.swift
//

import Foundation

struct PhaseGuideSection: Identifiable, Equatable {
    let id: Int
    let title: String
    let lines: [String]
}

struct PhaseGuideEntry: Equatable {
    let heading: String
    let timing: [String]
    let sections: [PhaseGuideSection]
}

enum PhaseGuideParser {
    /// Splits one raw phase block on blank lines: heading, timing, then titled sections.
    /// Does not alter any wording.
    static func parse(_ raw: String) -> PhaseGuideEntry {
        let paragraphs = raw
            .components(separatedBy: "\n\n")
            .map { $0.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
            .filter { !$0.isEmpty }
        let heading = paragraphs.first?.first ?? ""
        let timing = paragraphs.count > 1 ? paragraphs[1] : []
        let sections = paragraphs.dropFirst(2).enumerated().map { index, lines in
            PhaseGuideSection(id: index, title: lines[0], lines: Array(lines.dropFirst()))
        }
        return PhaseGuideEntry(heading: heading, timing: timing, sections: sections)
    }
}

enum PhaseGuideContent {
    /// Order matches Event.EventType.allCases: menstrual, follicular, ovulation, luteal.
    static let raw: [String] = [
"""
1. Menstrual Phase

Approximate Timing: Day 1 to Day 5
(Overlaps with the early part of the follicular phase)

What’s Happening Biologically
Hormones: Levels of estrogen and progesterone are relatively low at the start of menstruation because the corpus luteum (leftover from the previous cycle) is no longer producing high levels of progesterone.
Uterine Lining: The endometrium (uterine lining) sheds, leading to menstrual bleeding.

Pregnancy Probability
Very Low: Since menstruation generally marks the beginning of a new cycle and ovulation is still roughly 10–14 days away, the probability of becoming pregnant is minimal during this time. However, it is not absolutely zero-especially if someone has a shorter cycle or if sperm remains viable in the reproductive tract for several days.

Common Mood & Symptoms
Mood: Some individuals may experience relief from premenstrual syndrome (PMS) symptoms once bleeding begins, while others might still feel mood fluctuations (cramps, fatigue, irritability).
Physical Symptoms: Cramping (dysmenorrhea), bloating, backaches, breast tenderness, and headaches. Energy levels may be lower.

Tips/Benefits:
Warm compresses or gentle heat can help relieve cramps.
Staying hydrated and keeping up light, moderate exercise (such as yoga, walking) can improve mood and circulation.
Iron-rich foods or supplements may help if you’re prone to low iron due to menstrual blood loss (consult with a healthcare provider for personalized advice).
""",
"""
2. Follicular Phase

Approximate Timing: Day 1 to Day 13
(Begins on Day 1, overlaps with menstruation until bleeding stops; continues up to ovulation)

What’s Happening Biologically
Hormones: Follicle-stimulating hormone (FSH) from the pituitary gland stimulates ovarian follicles to develop. Estrogen levels begin to rise.
Ovarian Follicles: Several follicles start to mature, but usually only one becomes dominant and is prepared for ovulation.
Uterine Lining: The endometrium starts to thicken again under rising estrogen levels.

Pregnancy Probability
Increasing but Still Moderate: The closer you get to ovulation (toward the end of the follicular phase), the higher the chance of pregnancy if unprotected intercourse occurs. Sperm can survive up to about five days in fertile cervical mucus.

Common Mood & Symptoms
Mood: As estrogen climbs, many people notice improved mood, higher energy, clearer thinking, and an overall sense of well-being.
Physical Symptoms: A possible gradual boost in libido, more cervical fluid that is thinner and more elastic (“fertile mucus”), and potentially fewer PMS-like symptoms compared to the luteal phase.

Tips/Benefits:
This is often a good time for high-energy workouts and social activities.
If trying to conceive, tracking cervical mucus changes or using ovulation predictor kits can be helpful toward the end of the follicular phase.
""",
"""
3. Ovulatory Phase

Approximate Timing: Around Day 14 (in a 28-day cycle)

What’s Happening Biologically
Hormones: A surge in luteinizing hormone (LH) triggers the dominant follicle in the ovary to release the mature egg (ovum).
Ovulation: The egg is released into the fallopian tube, where it remains viable for about 12–24 hours.

Pregnancy Probability
Peak Fertility Window: This is the highest probability time for conception. Sperm present in the reproductive tract around ovulation (up to five days prior, day of, or shortly after) can fertilize the egg.

Common Mood & Symptoms
Mood: Often an uptick in libido, energy, and confidence due to peaking estrogen and testosterone levels.
Physical Symptoms: Some individuals experience mild pelvic twinges (Mittelschmerz), increased cervical mucus (clear, stretchy, “egg white” consistency), possibly a slight increase in basal body temperature after ovulation.

Tips/Benefits:
If trying to conceive, having intercourse in the days leading up to and including ovulation is key.
Staying hydrated and listening to your body can help manage any mild ovulatory discomfort.
""",
"""
4. Luteal Phase

Approximate Timing: Day 15 to Day 28

What’s Happening Biologically
Hormones: After the egg is released, the follicle transforms into the corpus luteum, which secretes progesterone (and some estrogen). Progesterone prepares the uterus for a possible pregnancy.
Uterine Lining: The endometrium becomes more glandular and thicker to potentially support an embryo.

Pregnancy Probability
Higher Early in the Luteal Phase, Then Decreases:
If fertilization and implantation occur, progesterone remains high (supported by human chorionic gonadotropin, or hCG) to sustain pregnancy.
If no implantation occurs, progesterone production drops, leading to the shedding of the uterine lining (menstruation).

Common Mood & Symptoms
Mood: Potential for PMS/PMDD symptoms due to falling progesterone and estrogen toward the end of the luteal phase if pregnancy does not occur. Symptoms may include irritability, low mood, anxiety, mood swings.
Physical Symptoms: Bloating, breast tenderness, fatigue, food cravings, changes in bowel habits, possible fluid retention.

Tips/Benefits:
Focus on nutrient-dense foods, balanced meals, and adequate hydration to stabilize mood and energy.
Moderate exercise, mindfulness, and stress-reduction techniques can alleviate PMS symptoms.
Tracking symptoms can help identify patterns and better manage the physical and emotional fluctuations.
"""
]
}
