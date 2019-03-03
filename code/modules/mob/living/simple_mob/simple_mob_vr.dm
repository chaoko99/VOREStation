// Flags for specifying which states we have vore icon_states for.
#define SA_ICON_LIVING	0x01
#define SA_ICON_DEAD	0x02
#define SA_ICON_REST	0x03

/mob/living/simple_mob
	var/vore_active = 0					// If vore behavior is enabled for this mob

	var/vore_capacity = 1				// The capacity (in people) this person can hold
	var/vore_max_size = RESIZE_HUGE		// The max size this mob will consider eating
	var/vore_min_size = RESIZE_TINY 	// The min size this mob will consider eating
	var/vore_bump_chance = 0			// Chance of trying to eat anyone that bumps into them, regardless of hostility
	var/vore_bump_emote	= "grabs hold of"				// Allow messages for bumpnom mobs to have a flavorful bumpnom
	var/vore_pounce_chance = 5			// Chance of this mob knocking down an opponent
	var/vore_pounce_cooldown = 0		// Cooldown timer - if it fails a pounce it won't pounce again for a while
	var/vore_pounce_successrate	= 100	// Chance of a pounce succeeding against a theoretical 0-health opponent
	var/vore_pounce_falloff = 1			// Success rate falloff per %health of target mob.
	var/vore_pounce_maxhealth = 80		// Mob will not attempt to pounce targets above this %health
	var/vore_standing_too = 0			// Can also eat non-stunned mobs
	var/vore_ignores_undigestable = 1	// Refuse to eat mobs who are undigestable by the prefs toggle.
	var/swallowsound = null				// What noise plays when you succeed in eating the mob.

	var/vore_default_mode = DM_DIGEST	// Default bellymode (DM_DIGEST, DM_HOLD, DM_ABSORB)
	var/vore_default_flags = DM_FLAG_ITEMWEAK // Itemweak by default
	var/vore_digest_chance = 25			// Chance to switch to digest mode if resisted
	var/vore_absorb_chance = 0			// Chance to switch to absorb mode if resisted
	var/vore_escape_chance = 25			// Chance of resisting out of mob

	var/vore_stomach_name				// The name for the first belly if not "stomach"
	var/vore_stomach_flavor				// The flavortext for the first belly if not the default

	var/vore_fullness = 0				// How "full" the belly is (controls icons)
	var/vore_icons = 0					// Bitfield for which fields we have vore icons for.
	var/life_disabled = 0				// For performance reasons

	var/mount_offset_x = 5				// Horizontal riding offset.
	var/mount_offset_y = 8				// Vertical riding offset

// Release belly contents before being gc'd!
/mob/living/simple_mob/Destroy()
	release_vore_contents()
	prey_excludes.Cut()
	. = ..()

//For all those ID-having mobs
/mob/living/simple_mob/GetIdCard()
	if(myid)
		return myid

// Update fullness based on size & quantity of belly contents
/mob/living/simple_mob/proc/update_fullness()
	var/new_fullness = 0
	for(var/belly in vore_organs)
		var/obj/belly/B = belly
		for(var/mob/living/M in B)
			new_fullness += M.size_multiplier
	new_fullness = round(new_fullness, 1) // Because intervals of 0.25 are going to make sprite artists cry.
	vore_fullness = min(vore_capacity, new_fullness)

/mob/living/simple_mob/proc/update_vore_icon()
	if(!vore_active)
		return 0
	update_fullness()
	if(!vore_fullness)
		return 0
	else if((stat == CONSCIOUS) && (!icon_rest || !resting || !incapacitated(INCAPACITATION_DISABLED)) && (vore_icons & SA_ICON_LIVING))
		return "[icon_living]-[vore_fullness]"
	else if(stat >= DEAD && (vore_icons & SA_ICON_DEAD))
		return "[icon_dead]-[vore_fullness]"
	else if(((stat == UNCONSCIOUS) || resting || incapacitated(INCAPACITATION_DISABLED) ) && icon_rest && (vore_icons & SA_ICON_REST))
		return "[icon_rest]-[vore_fullness]"

/mob/living/simple_mob/proc/will_eat(var/mob/living/M)
	if(client) //You do this yourself, dick!
		//ai_log("vr/wont eat [M] because we're player-controlled", 3) //VORESTATION AI TEMPORARY REMOVAL
		return 0
	if(!istype(M)) //Can't eat 'em if they ain't /mob/living
		//ai_log("vr/wont eat [M] because they are not /mob/living", 3) //VORESTATION AI TEMPORARY REMOVAL
		return 0
	if(src == M) //Don't eat YOURSELF dork
		//ai_log("vr/won't eat [M] because it's me!", 3) //VORESTATION AI TEMPORARY REMOVAL
		return 0
	if(vore_ignores_undigestable && !M.digestable) //Don't eat people with nogurgle prefs
		//ai_log("vr/wont eat [M] because I am picky", 3) //VORESTATION AI TEMPORARY REMOVAL
		return 0
	if(!M.allowmobvore) // Don't eat people who don't want to be ate by mobs
		//ai_log("vr/wont eat [M] because they don't allow mob vore", 3) //VORESTATION AI TEMPORARY REMOVAL
		return 0
	if(M in prey_excludes) // They're excluded
		//ai_log("vr/wont eat [M] because they are excluded", 3) //VORESTATION AI TEMPORARY REMOVAL
		return 0
	if(M.size_multiplier < vore_min_size || M.size_multiplier > vore_max_size)
		//ai_log("vr/wont eat [M] because they too small or too big", 3) //VORESTATION AI TEMPORARY REMOVAL
		return 0
	if(vore_capacity != 0 && (vore_fullness >= vore_capacity)) // We're too full to fit them
		//ai_log("vr/wont eat [M] because I am too full", 3) //VORESTATION AI TEMPORARY REMOVAL
		return 0
	return 1

/mob/living/simple_mob/apply_attack(atom/A, damage_to_do)
	if(isliving(A)) // Converts target to living
		var/mob/living/L = A

		//ai_log("vr/do_attack() [L]", 3)
		// If we're not hungry, call the sideways "parent" to do normal punching
		if(!vore_active)
			return ..()

		// If target is standing we might pounce and knock them down instead of attacking
		var/pouncechance = CanPounceTarget(L)
		if(pouncechance)
			return PounceTarget(L, pouncechance)

		// We're not attempting a pounce, if they're down or we can eat standing, do it as long as they're edible. Otherwise, hit normally.
		if(will_eat(L) && (!L.canmove || vore_standing_too))
			return EatTarget(L)
		else
			return ..()


/mob/living/simple_mob/proc/CanPounceTarget(var/mob/living/M) //returns either FALSE or a %chance of success
	if(!M.canmove || issilicon(M) || world.time < vore_pounce_cooldown) //eliminate situations where pouncing CANNOT happen
		return FALSE
	if(!prob(vore_pounce_chance)) //mob doesn't want to pounce
		return FALSE
	if(will_eat(M) && vore_standing_too) //100% chance of hitting people we can eat on the spot
		return 100
	var/TargetHealthPercent = (M.health/M.getMaxHealth())*100 //now we start looking at the target itself
	if (TargetHealthPercent > vore_pounce_maxhealth) //target is too healthy to pounce
		return FALSE
	else
		return max(0,(vore_pounce_successrate - (vore_pounce_falloff * TargetHealthPercent)))


/mob/living/simple_mob/proc/PounceTarget(var/mob/living/M, var/successrate = 100)
	vore_pounce_cooldown = world.time + 20 SECONDS // don't attempt another pounce for a while
	if(prob(successrate)) // pounce success!
		M.Weaken(5)
		M.visible_message("<span class='danger'>\the [src] pounces on \the [M]!</span>!")
	else // pounce misses!
		M.visible_message("<span class='danger'>\the [src] attempts to pounce \the [M] but misses!</span>!")
		playsound(loc, 'sound/weapons/punchmiss.ogg', 25, 1, -1)

	if(will_eat(M) && (!M.canmove || vore_standing_too)) //if they're edible then eat them too
		return EatTarget(M)
	else
		return //just leave them

// Attempt to eat target
// TODO - Review this.  Could be some issues here
/mob/living/simple_mob/proc/EatTarget(var/mob/living/M)
	//ai_log("vr/EatTarget() [M]",2) //VORESTATION AI TEMPORARY REMOVAL
	//stop_automated_movement = 1 //VORESTATION AI TEMPORARY REMOVAL
	var/old_target = M
	set_AI_busy(1) //VORESTATION AI TEMPORARY EDIT
	. = animal_nom(M)
	playsound(src, swallowsound, 50, 1)
	update_icon()

	if(.)
		// If we succesfully ate them, lose the target
		set_AI_busy(0) // lose_target(M) //Unsure what to put here. Replaced with set_AI_busy(1) //VORESTATION AI TEMPORARY EDIT
		return old_target
	else if(old_target == M)
		// If we didn't but they are still our target, go back to attack.
		// but don't run the handler immediately, wait until next tick
		// Otherwise we'll be in a possibly infinate loop
		set_AI_busy(0) //VORESTATION AI TEMPORARY EDIT
	//stop_automated_movement = 0 //VORESTATION AI TEMPORARY EDIT

/mob/living/simple_mob/death()
	release_vore_contents()
	. = ..()

// Make sure you don't call ..() on this one, otherwise you duplicate work.
/mob/living/simple_mob/init_vore()
	if(!vore_active || no_vore)
		return

	if(!IsAdvancedToolUser())
		verbs |= /mob/living/simple_mob/proc/animal_nom
		verbs |= /mob/living/proc/shred_limb

	if(LAZYLEN(vore_organs))
		return

	//A much more detailed version of the default /living implementation
	var/obj/belly/B = new /obj/belly(src)
	vore_selected = B
	B.immutable = 1
	B.name = vore_stomach_name ? vore_stomach_name : "stomach"
	B.desc = vore_stomach_flavor ? vore_stomach_flavor : "Your surroundings are warm, soft, and slimy. Makes sense, considering you're inside \the [name]."
	B.digest_mode = vore_default_mode
	B.mode_flags = vore_default_flags
	B.escapable = vore_escape_chance > 0
	B.escapechance = vore_escape_chance
	B.digestchance = vore_digest_chance
	B.absorbchance = vore_absorb_chance
	B.human_prey_swallow_time = swallowTime
	B.nonhuman_prey_swallow_time = swallowTime
	B.vore_verb = "swallow"
	B.emote_lists[DM_HOLD] = list( // We need more that aren't repetitive. I suck at endo. -Ace
		"The insides knead at you gently for a moment.",
		"The guts glorp wetly around you as some air shifts.",
		"The predator takes a deep breath and sighs, shifting you somewhat.",
		"The stomach squeezes you tight for a moment, then relaxes harmlessly.",
		"The predator's calm breathing and thumping heartbeat pulses around you.",
		"The warm walls kneads harmlessly against you.",
		"The liquids churn around you, though there doesn't seem to be much effect.",
		"The sound of bodily movements drown out everything for a moment.",
		"The predator's movements gently force you into a different position.")
	B.emote_lists[DM_DIGEST] = list(
		"The burning acids eat away at your form.",
		"The muscular stomach flesh grinds harshly against you.",
		"The caustic air stings your chest when you try to breathe.",
		"The slimy guts squeeze inward to help the digestive juices soften you up.",
		"The onslaught against your body doesn't seem to be letting up; you're food now.",
		"The predator's body ripples and crushes against you as digestive enzymes pull you apart.",
		"The juices pooling beneath you sizzle against your sore skin.",
		"The churning walls slowly pulverize you into meaty nutrients.",
		"The stomach glorps and gurgles as it tries to work you into slop.")

/mob/living/simple_mob/Bumped(var/atom/movable/AM, yes)
	if(ismob(AM))
		var/mob/tmob = AM
		if(will_eat(tmob) && !istype(tmob, type) && prob(vore_bump_chance) && !ckey) //check if they decide to eat. Includes sanity check to prevent cannibalism.
			if(tmob.canmove && prob(vore_pounce_chance)) //if they'd pounce for other noms, pounce for these too, otherwise still try and eat them if they hold still
				tmob.Weaken(5)
			tmob.visible_message("<span class='danger'>\the [src] [vore_bump_emote] \the [tmob]!</span>!")
			set_AI_busy(TRUE)
			animal_nom(tmob)
			update_icon()
			set_AI_busy(FALSE)
	..()
/* //Was replaced with suitable_turf_type, but that can be done later. //VORESTATION AI TEMPORARY REMOVAL
// Checks to see if mob doesn't like this kind of turf
/mob/living/simple_mob/avoid_turf(var/turf/turf)
	//So we only check if the parent didn't find anything terrible
	if((. = ..(turf)))
		return .

	if(istype(turf,/turf/unsimulated/floor/sky))
		return TRUE //Mobs aren't that stupid, probably
*/
//Grab = Nomf
/mob/living/simple_mob/UnarmedAttack(var/atom/A, var/proximity)
	. = ..()

	if(a_intent == I_GRAB && isliving(A) && !has_hands)
		animal_nom(A)

// Riding
/datum/riding/simple_mob
	keytype = /obj/item/weapon/material/twohanded/fluff/riding_crop // Crack!
	nonhuman_key_exemption = FALSE	// If true, nonhumans who can't hold keys don't need them, like borgs and simplemobs.
	key_name = "a riding crop"		// What the 'keys' for the thing being rided on would be called.
	only_one_driver = TRUE			// If true, only the person in 'front' (first on list of riding mobs) can drive.

/datum/riding/simple_mob/handle_vehicle_layer()
	ridden.layer = initial(ridden.layer)

/datum/riding/simple_mob/ride_check(mob/living/M)
	var/mob/living/L = ridden
	if(L.stat)
		force_dismount(M)
		return FALSE
	return TRUE

/datum/riding/simple_mob/force_dismount(mob/M)
	. =..()
	ridden.visible_message("<span class='notice'>[M] stops riding [ridden]!</span>")

/datum/riding/simple_mob/get_offsets(pass_index) // list(dir = x, y, layer)
	var/mob/living/simple_mob/L = ridden
	var/scale = L.size_multiplier

	var/list/values = list(
		"[NORTH]" = list(0, L.mount_offset_y*scale, ABOVE_MOB_LAYER),
		"[SOUTH]" = list(0, L.mount_offset_y*scale, BELOW_MOB_LAYER),
		"[EAST]" = list(-L.mount_offset_x*scale, L.mount_offset_y*scale, ABOVE_MOB_LAYER),
		"[WEST]" = list(L.mount_offset_x*scale, L.mount_offset_y*scale, ABOVE_MOB_LAYER))

	return values

/mob/living/simple_mob/buckle_mob(mob/living/M, forced = FALSE, check_loc = TRUE)
	if(forced)
		return ..() // Skip our checks
	if(!riding_datum)
		return FALSE
	if(lying)
		return FALSE
	if(!ishuman(M))
		return FALSE
	if(M in buckled_mobs)
		return FALSE
	if(M.size_multiplier > size_multiplier * 1.2)
		to_chat(src,"<span class='warning'>This isn't a pony show! You need to be bigger for them to ride.</span>")
		return FALSE

	var/mob/living/carbon/human/H = M

	if(H.loc != src.loc)
		if(H.Adjacent(src))
			H.forceMove(get_turf(src))

	. = ..()
	if(.)
		buckled_mobs[H] = "riding"

/mob/living/simple_mob/attack_hand(mob/user as mob)
	if(riding_datum && LAZYLEN(buckled_mobs))
		//We're getting off!
		if(user in buckled_mobs)
			riding_datum.force_dismount(user)
		//We're kicking everyone off!
		if(user == src)
			for(var/rider in buckled_mobs)
				riding_datum.force_dismount(rider)
	else
		. = ..()

/mob/living/simple_mob/proc/animal_mount(var/mob/living/M in living_mobs(1))
	set name = "Animal Mount/Dismount"
	set category = "Abilities"
	set desc = "Let people ride on you."

	if(LAZYLEN(buckled_mobs))
		for(var/rider in buckled_mobs)
			riding_datum.force_dismount(rider)
		return
	if (stat != CONSCIOUS)
		return
	if(!can_buckle || !istype(M) || !M.Adjacent(src) || M.buckled)
		return
	if(buckle_mob(M))
		visible_message("<span class='notice'>[M] starts riding [name]!</span>")
