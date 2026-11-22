# Doctors: what to check (owner D30)

You asked: "instead of being able to choose to play as police drone (operator) lets make that slot, (doctor) which (doctors) can also drive the ambulances as a role and job at the hospital when they are present to pick up bite victims. However, if they do not do so properly they get demoted back to human."

## What changed

- **The menu.** The fifth button is now **Doctor** ("Drive the ambulance and bring bite victims to the hospital."), in the hospital's teal. The Police drone is no longer a menu choice. (The drone itself is still parked at the police station and is still part of the police plans for later.)
- **Picking Doctor.** You become one of the hospital's people, standing on the pavement beside the ambulances parked on the hospital road. There are 5 doctor places. If all 5 are taken you read "Every doctor's place at the hospital is taken (5 of 5). Pick another body."
- **The call.** When someone the Spicy Rodent bit collapses and the hospital is called, a free doctor gets the call instead of the computer's ambulance. You see a big DOCTOR message ("Bite victim! Take an ambulance (E beside one on the hospital road) and drive there"), a teal **BITE VICTIM** marker over the patient, and a teal line under your status with the distance and direction ("BITE VICTIM WAITING · Take an ambulance (E) and drive there: 340 studs to your left").
- **The ambulance.** Press **E** beside one of the three parked ambulances: you get in and drive it. Its light bar flashes red and white while it is out. Only doctors can take one: anyone else reads "Only doctors drive the ambulances. Pick Doctor from the menu (M)."
- **Loading.** Stop beside the patient (slow to a stop within a few steps of them). If they lie somewhere you cannot drive up to (a fenced yard), park close, get out and walk up to them. They are put aboard and the marker moves to the hospital ("PATIENT ABOARD · Stop at the hospital doors").
- **Unloading.** Stop at the hospital doors (the hospital drive, or by the ambulance bays). The patient is taken in and the hospital treats and cures them exactly as before. You are paid **S$10.00** ("Patient brought in: +S$10.00", D31) and earn the hospital fetch's rank points (more the faster you got to the patient).
- **Not doing it properly.** If you do not set off for a call (get into an ambulance) or make no headway towards the patient or, with a patient aboard, towards the hospital (parked, out of the ambulance, driving the wrong way) for **60 seconds**, you get one warning: "Bite victim waiting: head there now or you will lose the job." (or "Your patient needs the hospital: drive there now or you will lose the job."). At **90 seconds** you are demoted: "NOT A DOCTOR ANY MORE", you are put out of the ambulance and are a townsperson again (the lowest rung). The computer's ambulance then goes for the patient (or, if they were aboard, the hospital takes them in), so the patient is always cured.
- **Nobody is left waiting.** With no doctor in the game, or every doctor busy, or a call that is still not reached after 5 minutes, the computer's ambulances handle it exactly as before.
- **Ambulances go home.** Leave one at the bays and it is parked back at once; leave it anywhere else and it goes back to its bay after a minute and a half with nobody near it.

## Please try

1. Pick **Doctor** from the menu (M). You should stand beside the ambulances on the hospital road. Your status says DOCTOR.
2. As another player (or wait for the town's rodent), get someone bitten so they collapse. Within about 10 seconds the doctor should get the call, the BITE VICTIM marker and the line.
3. Press E beside an ambulance, drive to the marker, stop beside the patient. They should disappear into the ambulance and the marker should move to the hospital.
4. Stop at the hospital doors. You should see "+S$10.00" and the patient should appear in a hospital bed and later walk home cured.
5. Take another call and ignore it: after a minute the warning, after a minute and a half the demotion banner, and a computer ambulance drives out for the patient.
6. As a townsperson, press E beside a parked ambulance: you should be told only doctors drive them.

## Not in this change

- **No siren sound.** The game has no siren in its sounds (the computer's ambulances are silent too); adding one needs an upload. The lights flash.
- The S$100 penalty for an ignored victim and the lowest money level after a demotion are the town work's part (D30, another helper): this change does the role change and tells the reputation in the background.
- Nothing here has been seen in the running game yet (the engine cannot be run from here): the rules were checked by the automatic tests on the real town.

## Cost

- No new parts in the town. An ambulance out with a doctor is the same drawing the traffic uses (at most 42 parts, the limit every player vehicle is held to), only while it is out (three at most); the fleet's own ambulance is hidden meanwhile.
- Server: the doctors' rules run five times a second, a few distance checks per doctor. Client: the flashing looks at the vehicle folder ten times a second and changes two parts per ambulance out.
