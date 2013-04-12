/**
 * This code was referenced in some headers without the definition actually
 * being included, thus factored out into a helper module.
 */
module deimos.event2._tailq;

/* Fix so that people don't have to run with <sys/queue.h> */
struct TAILQ_ENTRY(type) {
	type* tqe_next;	/* next element */
	type** tqe_prev;	/* address of previous next element */
}

mixin template TAILQ_HEAD(string name, type) {
	mixin(
		"struct " ~ name ~ "{" ~ q{
			type* tqh_first;
			type** tqh_last;
		} ~ "}"
	);
}
