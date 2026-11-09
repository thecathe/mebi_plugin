Set Debug "backtrace".
(* Declare the plugin first: the MeBi commands below, the dividers included,
   do not exist until it is loaded. *)
Declare ML Module "rocq-mebi.mebi".
MeBi Divider "Loading MeBi Plugin".
From MEBI Require Export Bisimilarity.
From MEBI Require Export Premises.
MeBi Config Output Wrap Flow.
MeBi Divider "Finished Loading MeBi Plugin".
