class_name VineLink
extends AnimatableBody3D

## One physics-collision node of a Vine chain.
## Vine._build_links() spawns LINK_COUNT of these as children of the Vine
## Node3D and repositions them every physics frame to match the verlet sim.
##
## collision_layer = 2  →  sits on the "vine" layer, separate from the player's
##                          layer 1, so CharacterBody3D.move_and_slide never
##                          tries to push the player away from the vine.
## collision_mask  = 0  →  the links themselves collide with nothing.
## The player's VineRay uses collision_mask = 3 (layers 1 + 2), so it can
## detect these links through open air but not through solid walls on layer 1.

## Back-reference to the Vine node that owns and simulates this link.
## Assigned by Vine._build_links() immediately after the node is created.
var root_vine : Vine
