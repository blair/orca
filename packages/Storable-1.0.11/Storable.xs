/*
 * Store and retrieve mechanism.
 */

/*
 * $Id: Storable.xs,v 0.6.1.8 2000/03/02 22:20:35 ram Exp $
 *
 *  Copyright (c) 1995-1998, Raphael Manfredi
 *  
 *  You may redistribute only under the terms of the Artistic License,
 *  as specified in the README file that comes with the distribution.
 *
 * $Log: Storable.xs,v $
 * Revision 0.6.1.8  2000/03/02 22:20:35  ram
 * patch9: include "patchlevel.h" for new perl 5.6
 * patch9: fixed "undef" bug in hash keys, reported by Albert N. Micheev
 *
 * Revision 0.6.1.7  2000/02/10 18:47:22  ram
 * patch8: added last_op_in_netorder() predicate
 *
 * Revision 0.6.1.6  1999/10/19 19:23:34  ram
 * patch6: Fixed typo in macro that made threaded code not compilable
 * patch6: Changed detection of older perls (pre-5.005) by testing PATCHLEVEL
 *
 * Revision 0.6.1.5  1999/09/14 20:12:29  ram
 * patch5: integrated "thread-safe" patch from Murray Nesbitt
 * patch5: try to avoid compilation warning on 64-bit CPUs
 *
 * Revision 0.6.1.4  1999/07/12  12:37:01  ram
 * patch4: uses new internal PL_* naming convention.
 *
 * Revision 0.6.1.3  1998/07/03  11:36:09  ram
 * patch3: fixed compatibility (wrt 0.5@9) for retrieval of blessed refs
 * patch3: increased store() throughput significantly
 *
 * Revision 0.6.1.2  1998/06/22  09:00:04  ram
 * patch2: adjust refcnt of tied objects after calling sv_magic()
 *
 * Revision 0.6.1.1  1998/06/12  09:46:48  ram
 * patch1: added workaround for persistent LVALUE-ness in perl5.004
 * patch1: now handles Perl immortal scalars explicitely
 * patch1: retrieval of non-immortal undef cannot be shared
 *
 * Revision 0.6  1998/06/04  16:08:22  ram
 * Baseline for first beta release.
 *
 */

#include "EXTERN.h"
#include "perl.h"
#include "patchlevel.h"		/* Perl's one, needed since 5.6 */
#include "XSUB.h"

/*#define DEBUGME /* Debug mode, turns assertions on as well */
/*#define DASSERT /* Assertion mode */

/*
 * Pre PerlIO time when none of USE_PERLIO and PERLIO_IS_STDIO is defined
 * Provide them with the necessary defines so they can build with pre-5.004.
 */
#ifndef USE_PERLIO
#ifndef PERLIO_IS_STDIO
#define PerlIO FILE
#define PerlIO_getc(x) getc(x)
#define PerlIO_putc(f,x) putc(x,f)
#define PerlIO_read(x,y,z) fread(y,1,z,x)
#define PerlIO_write(x,y,z) fwrite(y,1,z,x)
#define PerlIO_stdoutf printf
#endif	/* PERLIO_IS_STDIO */
#endif	/* USE_PERLIO */

/*
 * Earlier versions of perl might be used, we can't assume they have the latest!
 */
#ifndef newRV_noinc
#define newRV_noinc(sv)		((Sv = newRV(sv)), --SvREFCNT(SvRV(Sv)), Sv)
#endif
#if (PATCHLEVEL <= 4)		/* Older perls (<= 5.004) lack PL_ namespace */
#define PL_sv_yes	sv_yes
#define PL_sv_no	sv_no
#define PL_sv_undef	sv_undef
#endif
#ifndef HvSHAREKEYS_off
#define HvSHAREKEYS_off(hv)	/* Ignore */
#endif

#ifdef DEBUGME
#ifndef DASSERT
#define DASSERT
#endif
#define TRACEME(x)	do { PerlIO_stdoutf x; PerlIO_stdoutf("\n"); } while (0)
#else
#define TRACEME(x)
#endif

#ifdef DASSERT
#define ASSERT(x,y)	do { \
	if (!x) { PerlIO_stdoutf y; PerlIO_stdoutf("\n"); }} while (0)
#else
#define ASSERT(x,y)
#endif

/*
 * Type markers.
 */

#define C(x) ((char) (x))	/* For markers with dynamic retrieval handling */

#define SX_OBJECT	C(0)	/* Already stored object */
#define SX_LSCALAR	C(1)	/* Scalar (string) forthcoming (length, data) */
#define SX_ARRAY	C(2)	/* Array forthcominng (size, item list) */
#define SX_HASH		C(3)	/* Hash forthcoming (size, key/value pair list) */
#define SX_REF		C(4)	/* Reference to object forthcoming */
#define SX_UNDEF	C(5)	/* Undefined scalar */
#define SX_INTEGER	C(6)	/* Integer forthcoming */
#define SX_DOUBLE	C(7)	/* Double forthcoming */
#define SX_BYTE		C(8)	/* (signed) byte forthcoming */
#define SX_NETINT	C(9)	/* Integer in network order forthcoming */
#define SX_SCALAR	C(10)	/* Scalar (small) forthcoming (length, data) */
#define SX_TIED_ARRAY  C(11)  /* Tied array forthcoming */
#define SX_TIED_HASH   C(12)  /* Tied hash forthcoming */
#define SX_TIED_SCALAR C(13)  /* Tied scalar forthcoming */
#define SX_SV_UNDEF	C(14)	/* Perl's immortal PL_sv_undef */
#define SX_SV_YES	C(15)	/* Perl's immortal PL_sv_yes */
#define SX_SV_NO	C(16)	/* Perl's immortal PL_sv_no */
#define SX_ERROR	C(17)	/* Error */

/*
 * Those are only used to retrieve "old" pre-0.6 binary images.
 */
#define SX_ITEM		'i'		/* An array item introducer */
#define SX_IT_UNDEF	'I'		/* Undefined array item */
#define SX_KEY		'k'		/* An hash key introducer */
#define SX_VALUE	'v'		/* An hash value introducer */
#define SX_VL_UNDEF	'V'		/* Undefined hash value */

/*
 * Notification markers.
 */

#define SX_BLESS	'b'		/* Object is blessed, class name length <255 */
#define SX_LG_BLESS	'B'		/* Object is blessed, class name length >255 */
#define SX_STORED	'X'		/* End of object */

#define LG_BLESS	255		/* Large blessing classname length limit */
#define LG_SCALAR	255		/* Large scalar length limit */

/*
 * The following structure is used for hash table key retrieval. Since, when
 * retrieving objects, we'll be facing blessed hash references, it's best
 * to pre-allocate that buffer once and resize it as the need arises, never
 * freeing it (keys will be saved away someplace else anyway, so even large
 * keys are not enough a motivation to reclaim that space).
 *
 * This structure is also used for memory store/retrieve operations which
 * happen in a fixed place before being malloc'ed elsewhere if persistency
 * is required. Hence the aptr pointer.
 */
struct extendable {
	char *arena;		/* Will hold hash key strings, resized as needed */
	STRLEN asiz;		/* Size of aforementionned buffer */
	char *aptr;			/* Arena pointer, for in-place read/write ops */
	char *aend;			/* First invalid address */
};

/*
 * At store time:
 * This hash table records the objects which have already been stored.
 * Those are referred to as SX_OBJECT in the file, and their "tag" (i.e.
 * an arbitrary sequence number) is used to identify them.
 *
 * At retrieve time:
 * This array table records the objects which have already been retrieved,
 * as seen by the tag determind by counting the objects themselves. The
 * reference to that retrieved object is kept in the table, and is returned
 * when an SX_OBJECT is found bearing that same tag.
 */

typedef unsigned long stag_t;	/* Used by pre-0.6 binary format */

/*
 * The following "thread-safe" related defines were contributed by
 * Murray Nesbitt <murray@activestate.com> and integrated by RAM, who
 * only renamed things a little bit to ensure consistency with surrounding
 * code.
 *
 * The patch itself is fairly inefficient since it performs a lookup in
 * some hash table at the start of every routine. It has to do that in order
 * to determine the proper context.
 *
 * The right solution, naturally, is to change all the signatures to propagate
 * the context down the call chain and only fetch the per-thread context only
 * once at the entry point before recursion begins. That's planned for some
 * day, when Perl's threading model will be stabilized.
 *
 *		-- RAM, 14/09/1999
 */

#define MY_VERSION "Storable(" XS_VERSION ")"

typedef struct {
    HV *hseen;			/* which objects have been seen, store time */
    AV *aseen;			/* which objects have been seen, retrieve time */
    I32 tagnum;			/* incremented at store time for each seen object */
    int netorder;		/* true if network order used */
    int forgive_me;		/* whether to be forgiving... */
    int canonical;		/* whether to store hashes sorted by key */
    struct extendable keybuf;	/* for hash key retrieval */
    struct extendable membuf;	/* for memory store/retrieve operations */
} storable_cxt_t;

#if defined(MULTIPLICITY) || defined(PERL_OBJECT) || defined(PERL_CAPI)

#if (PATCHLEVEL <= 4) && (SUBVERSION < 68)
#define dPERINTERP_SV 									\
	SV *perinterp_sv = perl_get_sv(MY_VERSION, FALSE)
#else	/* >= perl5.004_68 */
#define dPERINTERP_SV									\
	SV *perinterp_sv = *hv_fetch(PL_modglobal,			\
		MY_VERSION, sizeof(MY_VERSION)-1, TRUE)
#endif	/* < perl5.004_68 */

#define dPERINTERP_PTR(T,name)							\
	T name = (T)(perinterp_sv && SvIOK(perinterp_sv)	\
				? SvIVX(perinterp_sv) : NULL)
#define dPERINTERP										\
	dPERINTERP_SV;										\
	dPERINTERP_PTR(storable_cxt_t *, PERINTERP)

#define INIT_PERINTERP									\
      dPERINTERP;										\
      Newz(0,PERINTERP,1, storable_cxt_t);				\
      sv_setiv(perinterp_sv, (IV)PERINTERP)

#else /* !MULTIPLICITY && !PERL_OBJECT && !PERL_CAPI */

static storable_cxt_t Context;
#define dPERINTERP typedef int _interp_DBI_dummy
#define PERINTERP (&Context)
#define INIT_PERINTERP

#endif /* MULTIPLICITY || PERL_OBJECT || PERL_CAPI */

#define hseen           (PERINTERP->hseen)
#define aseen           (PERINTERP->aseen)
#define tagnum          (PERINTERP->tagnum)
#define netorder        (PERINTERP->netorder)
#define forgive_me      (PERINTERP->forgive_me)
#define canonical       (PERINTERP->canonical)
#define keybuf          (PERINTERP->keybuf)
#define membuf          (PERINTERP->membuf)

/*
 * End of "thread-safe" related definitions.
 */

/*
 * key buffer handling
 */
#define kbuf	keybuf.arena
#define ksiz	keybuf.asiz
#define KBUFINIT() do {					\
	if (!kbuf) {						\
		TRACEME(("** allocating kbuf of 128 bytes")); \
		New(10003, kbuf, 128, char);	\
		ksiz = 128;						\
	}									\
} while (0)
#define KBUFCHK(x) do {			\
	if (x >= ksiz) {			\
		TRACEME(("** extending kbuf to %d bytes", x+1)); \
		Renew(kbuf, x+1, char);	\
		ksiz = x+1;				\
	}							\
} while (0)

/*
 * memory buffer handling
 */
#define mbase	membuf.arena
#define msiz	membuf.asiz
#define mptr	membuf.aptr
#define mend	membuf.aend
#define MGROW	(1 << 13)
#define MMASK	(MGROW - 1)

#define round_mgrow(x)	\
	((unsigned long) (((unsigned long) (x) + MMASK) & ~MMASK))
#define trunc_int(x)	\
	((unsigned long) ((unsigned long) (x) & ~(sizeof(int)-1)))
#define int_aligned(x)	\
	((unsigned long) (x) == trunc_int(x))

#define MBUF_INIT(x) do {				\
	if (!mbase) {						\
		TRACEME(("** allocating mbase of %d bytes", MGROW)); \
		New(10003, mbase, MGROW, char);	\
		msiz = MGROW;					\
	}									\
	mptr = mbase;						\
	if (x)								\
		mend = mbase + x;				\
	else								\
		mend = mbase + msiz;			\
} while (0)

#define MBUF_SIZE()	(mptr - mbase)

/*
 * Use SvPOKp(), because SvPOK() fails on tainted scalars.
 * See store_scalar() for other usage of this workaround.
 */
#define MBUF_LOAD(v) do {				\
	if (!SvPOKp(v))						\
		croak("Not a scalar string");	\
	mptr = mbase = SvPV(v, msiz);		\
	mend = mbase + msiz;				\
} while (0)

#define MBUF_XTEND(x) do {			\
	int nsz = (int) round_mgrow((x)+msiz);	\
	int offset = mptr - mbase;		\
	TRACEME(("** extending mbase to %d bytes", nsz));	\
	Renew(mbase, nsz, char);		\
	msiz = nsz;						\
	mptr = mbase + offset;			\
	mend = mbase + nsz;				\
} while (0)

#define MBUF_CHK(x) do {			\
	if ((mptr + (x)) > mend)		\
		MBUF_XTEND(x);				\
} while (0)

#define MBUF_GETC(x) do {			\
	if (mptr < mend)				\
		x = (int) (unsigned char) *mptr++;	\
	else							\
		return (SV *) 0;			\
} while (0)

#define MBUF_GETINT(x) do {				\
	if ((mptr + sizeof(int)) <= mend) {	\
		if (int_aligned(mptr))			\
			x = *(int *) mptr;			\
		else							\
			memcpy(&x, mptr, sizeof(int));	\
		mptr += sizeof(int);			\
	} else								\
		return (SV *) 0;				\
} while (0)

#define MBUF_READ(x,s) do {			\
	if ((mptr + (s)) <= mend) {		\
		memcpy(x, mptr, s);			\
		mptr += s;					\
	} else							\
		return (SV *) 0;			\
} while (0)

#define MBUF_SAFEREAD(x,s,z) do {	\
	if ((mptr + (s)) <= mend) {		\
		memcpy(x, mptr, s);			\
		mptr += s;					\
	} else {						\
		sv_free(z);					\
		return (SV *) 0;			\
	}								\
} while (0)

#define MBUF_PUTC(c) do {			\
	if (mptr < mend)				\
		*mptr++ = (char) c;			\
	else {							\
		MBUF_XTEND(1);				\
		*mptr++ = (char) c;			\
	}								\
} while (0)

#define MBUF_PUTINT(i) do {			\
	MBUF_CHK(sizeof(int));			\
	if (int_aligned(mptr))			\
		*(int *) mptr = i;			\
	else							\
		memcpy(mptr, &i, sizeof(int));	\
	mptr += sizeof(int);			\
} while (0)

#define MBUF_WRITE(x,s) do {		\
	MBUF_CHK(s);					\
	memcpy(mptr, x, s);				\
	mptr += s;						\
} while (0)


#define mbuf	membuf.arena
#define msiz	membuf.asiz

#define svis_REF	0
#define svis_SCALAR	1
#define svis_ARRAY	2
#define svis_HASH	3
#define svis_TIED	4
#define svis_OTHER	5

/*
 * Before 0.6, the magic string was "perl-store" (binary version number 0).
 *
 * Since 0.6 introduced many binary incompatibilities, the magic string has
 * been changed to "pst0" to allow an old image to be properly retrieved by
 * a newer Storable, but ensure a newer image cannot be retrieved with an
 * older version.
 */
static char old_magicstr[] = "perl-store";	/* Magic number before 0.6 */
static char magicstr[] = "pst0";			/* Used as a magic number */

#define STORABLE_BINARY		1				/* Binary "version" number */

/*
 * Useful store shortcuts...
 */
#define PUTMARK(x) do {					\
	if (!f)								\
		MBUF_PUTC(x);					\
	else if (PerlIO_putc(f, x) == EOF)	\
		return -1;						\
	} while (0)

#ifdef HAS_HTONL
#define WLEN(x)	do {				\
	if (netorder) {					\
		int y = (int) htonl(x);		\
		if (!f)						\
			MBUF_PUTINT(y);			\
		else if (PerlIO_write(f, &y, sizeof(y)) != sizeof(y))	\
			return -1;				\
	} else {						\
		if (!f)						\
			MBUF_PUTINT(x);			\
		else if (PerlIO_write(f, &x, sizeof(x)) != sizeof(x))	\
			return -1;				\
	}								\
} while (0)
#else
#define WLEN(x)	do {				\
	if (!f)							\
		MBUF_PUTINT(x);				\
	else if (PerlIO_write(f, &x, sizeof(x)) != sizeof(x))	\
		return -1;					\
	} while (0)
#endif

#define WRITE(x,y) do {						\
	if (!f)									\
		MBUF_WRITE(x,y);					\
	else if (PerlIO_write(f, x, y) != y)	\
		return -1;							\
	} while (0)

#define STORE_SCALAR(pv, len) do {		\
	if (len <= LG_SCALAR) {				\
		unsigned char clen = (unsigned char) len;	\
		PUTMARK(SX_SCALAR);				\
		PUTMARK(clen);					\
		if (len)						\
			WRITE(pv, len);				\
	} else {							\
		PUTMARK(SX_LSCALAR);			\
		WLEN(len);						\
		WRITE(pv, len);					\
	}									\
} while (0)

/*
 * Store undef in arrays and hashes without recusrsing through store().
 */
#define STORE_UNDEF() do {				\
	tagnum++;							\
	PUTMARK(SX_UNDEF);					\
	PUTMARK(SX_STORED);					\
} while (0)

/*
 * Useful retrieve shortcuts...
 */

#define GETCHAR() \
	(f ? PerlIO_getc(f) : (mptr >= mend ? EOF : (int) *mptr++))

#define GETMARK(x) do {						\
	if (!f)									\
		MBUF_GETC(x);						\
	else if ((x = PerlIO_getc(f)) == EOF)	\
		return (SV *) 0;					\
} while (0)

#ifdef HAS_NTOHL
#define RLEN(x)	do {					\
	if (!f)								\
		MBUF_GETINT(x);					\
	else if (PerlIO_read(f, &x, sizeof(x)) != sizeof(x))	\
		return (SV *) 0;				\
	if (netorder)						\
		x = (int) ntohl(x);				\
} while (0)
#else
#define RLEN(x)	do {					\
	if (!f)								\
		MBUF_GETINT(x);					\
	else if (PerlIO_read(f, &x, sizeof(x)) != sizeof(x))	\
		return (SV *) 0;				\
} while (0)
#endif

#define READ(x,y) do {					\
	if (!f)								\
		MBUF_READ(x, y);				\
	else if (PerlIO_read(f, x, y) != y)	\
		return (SV *) 0;				\
} while (0)

#define SAFEREAD(x,y,z) do { 				\
	if (!f)									\
		MBUF_SAFEREAD(x,y,z);				\
	else if (PerlIO_read(f, x, y) != y)	 {	\
		sv_free(z);							\
		return (SV *) 0;					\
	}										\
} while (0)

/*
 * This macro is used at retrieve time, to remember where object 'y', bearing a
 * given tag 'tagnum', has been retrieved. Next time we see an SX_OBJECT marker,
 * we'll therefore know where it has been retrieved and will be able to
 * share the same reference, as in the original stored memory image.
 */
#define SEEN(y) do {						\
	if (!y)									\
		return (SV *) 0;					\
	if (av_store(aseen, tagnum++, SvREFCNT_inc(y)) == 0) \
		return (SV *) 0;					\
	TRACEME(("aseen(#%d) = 0x%lx (refcnt=%d)", tagnum-1, \
		(unsigned long) y, SvREFCNT(y)-1)); \
	} while (0)

static int store();
static SV *retrieve();

/*
 * store_ref
 *
 * Store a reference.
 * Layout is SX_REF <object>.
 */
static int store_ref(f, sv)
PerlIO *f;
SV *sv;
{
	dPERINTERP;
	TRACEME(("store_ref (0x%lx)", (unsigned long) sv));

	PUTMARK(SX_REF);
	sv = SvRV(sv);
	return store(f, sv);
}

/*
 * store_scalar
 *
 * Store a scalar.
 *
 * Layout is SX_LSCALAR <length> <data>, SX_SCALAR <lenght> <data> or SX_UNDEF.
 * The <data> section is omitted if <length> is 0.
 *
 * If integer or double, the layout is SX_INTEGER <data> or SX_DOUBLE <data>.
 * Small integers (within [-127, +127]) are stored as SX_BYTE <byte>.
 */
static int store_scalar(f, sv)
PerlIO *f;
SV *sv;
{
	dPERINTERP;
	IV iv;
	char *pv;
	STRLEN len;
	U32 flags = SvFLAGS(sv);			/* "cc -O" may put it in register */

	TRACEME(("store_scalar (0x%lx)", (unsigned long) sv));

	/*
	 * For efficiency, break the SV encapsulation by peaking at the flags
	 * directly without using the Perl macros to avoid dereferencing
	 * sv->sv_flags each time we wish to check the flags.
	 */

	if (!(flags & SVf_OK)) {			/* !SvOK(sv) */
		if (sv == &PL_sv_undef) {
			TRACEME(("immortal undef"));
			PUTMARK(SX_SV_UNDEF);
		} else {
			TRACEME(("undef at 0x%x", sv));
			PUTMARK(SX_UNDEF);
		}
		return 0;
	}

	/*
	 * Always store the string representation of a scalar if it exists.
	 * Gisle Aas provided me with this test case, better than a long speach:
	 *
	 *  perl -MDevel::Peek -le '$a="abc"; $a+0; Dump($a)'
	 *  SV = PVNV(0x80c8520)
	 *       REFCNT = 1
	 *       FLAGS = (NOK,POK,pNOK,pPOK)
	 *       IV = 0
	 *       NV = 0
	 *       PV = 0x80c83d0 "abc"\0
	 *       CUR = 3
	 *       LEN = 4
	 *
	 * Write SX_SCALAR, length, followed by the actual data.
	 *
	 * Otherwise, write an SX_BYTE, SX_INTEGER or an SX_DOUBLE as
	 * appropriate, followed by the actual (binary) data. A double
	 * is written as a string if network order, for portability.
	 *
	 * NOTE: instead of using SvNOK(sv), we test for SvNOKp(sv).
	 * The reason is that when the scalar value is tainted, the SvNOK(sv)
	 * value is false.
	 *
	 * The test for a read-only scalar with both POK and NOK set is meant
	 * to quickly detect &PL_sv_yes and &PL_sv_no without having to pay the
	 * address comparison for each scalar we store.
	 */

#define SV_MAYBE_IMMORTAL (SVf_READONLY|SVf_POK|SVf_NOK)

	if ((flags & SV_MAYBE_IMMORTAL) == SV_MAYBE_IMMORTAL) {
		if (sv == &PL_sv_yes) {
			TRACEME(("immortal yes"));
			PUTMARK(SX_SV_YES);
		} else if (sv == &PL_sv_no) {
			TRACEME(("immortal no"));
			PUTMARK(SX_SV_NO);
		} else {
			pv = SvPV(sv, len);			/* We know it's SvPOK */
			goto string;				/* Share code below */
		}
	} else if (flags & SVp_POK) {		/* SvPOKp(sv) => string */
		pv = SvPV(sv, len);

		/*
		 * Will come here from below with pv and len set if double & netorder,
		 * or from above if it was readonly, POK and NOK but neither &PL_sv_yes
		 * nor &PL_sv_no.
		 */
	string:

		STORE_SCALAR(pv, len);
		TRACEME(("ok (scalar 0x%lx '%s', length = %d)",
			(unsigned long) sv, SvPVX(sv), len));

	} else if (flags & SVp_NOK) {		/* SvNOKp(sv) => double */
		double nv = SvNV(sv);

		/*
		 * Watch for number being an integer in disguise.
		 */
		if (nv == (double) (iv = I_V(nv))) {
			TRACEME(("double %lf is actually integer %ld", nv, iv));
			goto integer;		/* Share code below */
		}

		if (netorder) {
			TRACEME(("double %lf stored as string", nv));
			pv = SvPV(sv, len);
			goto string;		/* Share code below */
		}

		PUTMARK(SX_DOUBLE);
		WRITE(&nv, sizeof(nv));

		TRACEME(("ok (double 0x%lx, value = %lf)", (unsigned long) sv, nv));

	} else if (flags & SVp_IOK) {		/* SvIOKp(sv) => integer */
		iv = SvIV(sv);

		/*
		 * Will come here from above with iv set if double is an integer.
		 */
	integer:

		/*
		 * Optimize small integers into a single byte, otherwise store as
		 * a real integer (converted into network order if they asked).
		 */

		if (iv >= -128 && iv <= 127) {
			unsigned char siv = (unsigned char) (iv + 128);	/* [0,255] */
			PUTMARK(SX_BYTE);
			PUTMARK(siv);
			TRACEME(("small integer stored as %d", siv));
		} else if (netorder) {
			int niv;
#ifdef HAS_HTONL
			niv = (int) htonl(iv);
			TRACEME(("using network order"));
#else
			niv = (int) iv;
			TRACEME(("as-is for network order"));
#endif
			PUTMARK(SX_NETINT);
			WRITE(&niv, sizeof(niv));
		} else {
			PUTMARK(SX_INTEGER);
			WRITE(&iv, sizeof(iv));
		}

		TRACEME(("ok (integer 0x%lx, value = %d)", (unsigned long) sv, iv));

	} else
		croak("Can't determine type of %s(0x%lx)", sv_reftype(sv, FALSE),
			(unsigned long) sv);

	return 0;		/* Ok, no recursion on scalars */
}

/*
 * store_array
 *
 * Store an array.
 *
 * Layout is SX_ARRAY <size> followed by each item, in increading index order.
 * Each item is stored as <object>.
 */
static int store_array(f, av)
PerlIO *f;
AV *av;
{
	dPERINTERP;
	SV **sav;
	I32 len = av_len(av) + 1;
	I32 i;
	int ret;

	TRACEME(("store_array (0x%lx)", (unsigned long) av));

	/* 
	 * Signal array by emitting SX_ARRAY, followed by the array length.
	 */

	PUTMARK(SX_ARRAY);
	WLEN(len);
	TRACEME(("size = %d", len));

	/*
	 * Now store each item recursively.
	 */

	for (i = 0; i < len; i++) {
		sav = av_fetch(av, i, 0);
		if (!sav) {
			TRACEME(("(#%d) undef item", i));
			STORE_UNDEF();
			continue;
		}
		TRACEME(("(#%d) item", i));
		if (ret = store(f, *sav))
			return ret;
	}

	TRACEME(("ok (array)"));

	return 0;
}

/*
 * sortcmp
 *
 * Sort two SVs
 * Borrowed from perl source file pp_ctl.c, where it is used by pp_sort.
 */
static int
sortcmp(a, b)
const void *a;
const void *b;
{
	return sv_cmp(*(SV * const *) a, *(SV * const *) b);
}


/*
 * store_hash
 *
 * Store an hash table.
 *
 * Layout is SX_HASH <size> followed by each key/value pair, in random order.
 * Values are stored as <object>.
 * Keys are stored as <length> <data>, the <data> section being omitted
 * if length is 0.
 */
static int store_hash(f, hv)
PerlIO *f;
HV *hv;
{
	dPERINTERP;
	I32 len = HvKEYS(hv);
	I32 i;
	int ret = 0;
	I32 riter;
	HE *eiter;

	TRACEME(("store_hash (0x%lx)", (unsigned long) hv));

	/* 
	 * Signal hash by emitting SX_HASH, followed by the table length.
	 */

	PUTMARK(SX_HASH);
	WLEN(len);
	TRACEME(("size = %d", len));

	/*
	 * Save possible iteration state via each() on that table.
	 */

	riter = HvRITER(hv);
	eiter = HvEITER(hv);
	hv_iterinit(hv);

	/*
	 * Now store each item recursively.
	 *
     * If canonical is defined to some true value then store each
     * key/value pair in sorted order otherwise the order is random.
	 *
	 * Fetch the value from perl only once per store() operation, and only
	 * when needed.
	 */

	if (
		canonical == 1 ||
		(canonical < 0 && (canonical =
			SvTRUE(perl_get_sv("Storable::canonical", TRUE)) ? 1 : 0))
	) {
		/*
		 * Storing in order, sorted by key.
		 * Run through the hash, building up an array of keys in a
		 * mortal array, sort the array and then run through the
		 * array.  
		 */

		AV *av = newAV();

		TRACEME(("using canonical order"));

		for (i = 0; i < len; i++) {
			HE *he = hv_iternext(hv);
			SV *key = hv_iterkeysv(he);
			av_push(av, key);
		}
			
		qsort((char *) AvARRAY(av), len, sizeof(SV *), sortcmp);

		for (i = 0; i < len; i++) {
			char *keyval;
			I32 keylen;
			SV *key = av_shift(av);
			HE *he  = hv_fetch_ent(hv, key, 0, 0);
			SV *val = HeVAL(he);
			if (val == 0)
				return 1;		/* Internal error, not I/O error */
			
			/*
			 * Store value first, if defined.
			 */
			
			if (!SvOK(val)) {
				/*
				 * If the "undef" has a refcnt greater than one, other parts
				 * of the structure might reference this, so we cannot call
				 * STORE_UNDEF(): at retrieval time, we would break the
				 * relationship.  Thanks to Albert Micheev for exhibiting
				 * a structure where this bug manifested -- RAM, 02/03/2000.
				 */
				if (SvREFCNT(val) == 1) {
					TRACEME(("undef value"));
					STORE_UNDEF();
				} else {
					TRACEME(("undef value with refcnt=%d", SvREFCNT(val)));
					if (ret = store(f, val))
						goto out;
				}
			} else {
				TRACEME(("(#%d) value 0x%lx", i, (unsigned long) val));
				if (ret = store(f, val))
					goto out;
			}

			/*
			 * Write key string.
			 * Keys are written after values to make sure retrieval
			 * can be optimal in terms of memory usage, where keys are
			 * read into a fixed unique buffer called kbuf.
			 * See retrieve_hash() for details.
			 */
			 
			keyval = hv_iterkey(he, &keylen);
			TRACEME(("(#%d) key '%s'", i, keyval));
			WLEN(keylen);
			if (keylen)
				WRITE(keyval, keylen);
		}

		/* 
		 * Free up the temporary array
		 */

		av_undef(av);
		sv_free((SV *) av);

	} else {

		/*
		 * Storing in "random" order (in the order the keys are stored
		 * within the the hash).  This is the default and will be faster!
		 */
  
		for (i = 0; i < len; i++) {
			char *key;
			I32 len;
			SV *val = hv_iternextsv(hv, &key, &len);

			if (val == 0)
				return 1;		/* Internal error, not I/O error */

			/*
			 * Store value first, if defined.
			 */

			if (!SvOK(val)) {
				/*
				 * See comment above in the "canonical" section.
				 */
				if (SvREFCNT(val) == 1) {
					TRACEME(("undef value"));
					STORE_UNDEF();
				} else {
					TRACEME(("undef value with refcnt=%d", SvREFCNT(val)));
					if (ret = store(f, val))
						goto out;
				}
			} else {
				TRACEME(("(#%d) value 0x%lx", i, (unsigned long) val));
				if (ret = store(f, val))
					goto out;
			}

			/*
			 * Write key string.
			 * Keys are written after values to make sure retrieval
			 * can be optimal in terms of memory usage, where keys are
			 * read into a fixed unique buffer called kbuf.
			 * See retrieve_hash() for details.
			 */

			TRACEME(("(#%d) key '%s'", i, key));
			WLEN(len);
			if (len)
				WRITE(key, len);
		}
    }

	TRACEME(("ok (hash 0x%lx)", (unsigned long) hv));

out:
	HvRITER(hv) = riter;		/* Restore hash iterator state */
	HvEITER(hv) = eiter;

	return ret;
}

/*
 * store_tied
 *
 * When storing a tied object (be it a tied scalar, array or hash), we lay out
 * a special mark, followed by the underlying tied object. For instance, when
 * dealing with a tied hash, we store SX_TIED_HASH <hash object>, where
 * <hash object> stands for the serialization of the tied hash.
 */
static int store_tied(f, sv)
PerlIO *f;
SV *sv;
{
	dPERINTERP;
	MAGIC *mg;
	int ret = 0;
	int svt = SvTYPE(sv);
	char mtype = 'P';

	TRACEME(("store_tied (0x%lx)", (unsigned long) sv));

	/*
	 * We have a small run-time penalty here because we chose to factorise
	 * all tieds objects into the same routine, and not have a store_tied_hash,
	 * a store_tied_array, etc...
	 *
	 * Don't use a switch() statement, as most compilers don't optimize that
	 * well for 2/3 values. An if() else if() cascade is just fine. We put
	 * tied hashes first, as they are the most likely beasts.
	 */

	if (svt == SVt_PVHV) {
		TRACEME(("tied hash"));
		PUTMARK(SX_TIED_HASH);			/* Introduces tied hash */
	} else if (svt == SVt_PVAV) {
		TRACEME(("tied array"));
		PUTMARK(SX_TIED_ARRAY);			/* Introduces tied array */
	} else {
		TRACEME(("tied scalar"));
		PUTMARK(SX_TIED_SCALAR);		/* Introduces tied scalar */
		mtype = 'q';
	}

	if (!(mg = mg_find(sv, mtype)))
		croak("No magic '%c' found while storing tied %s", mtype,
			(svt == SVt_PVHV) ? "hash" :
				(svt == SVt_PVAV) ? "array" : "scalar");

	/*
	 * The mg->mg_obj found by mg_find() above actually points to the
	 * underlying tied Perl object implementation. For instance, if the
	 * original SV was that of a tied array, then mg->mg_obj is an AV.
	 *
	 * Note that we store the Perl object as-is. We don't call its FETCH
	 * method along the way. At retrieval time, we won't call its STORE
	 * method either, but the tieing magic will be re-installed. In itself,
	 * that ensures that the tieing semantics are preserved since futher
	 * accesses on the retrieved object will indeed call the magic methods...
	 */

	if (ret = store(f, mg->mg_obj))
		return ret;

	TRACEME(("ok (tied)"));

	return 0;
}

/*
 * store_other
 *
 * We don't know how to store the item we reached, so return an error condition.
 * (it's probably a GLOB, some CODE reference, etc...)
 *
 * If they defined the `forgive_me' variable at the Perl level to some
 * true value, then don't croak, just warn, and store a placeholder string
 * instead.
 */
static int store_other(f, sv)
PerlIO *f;
SV *sv;
{
	dPERINTERP;
	STRLEN len;
	static char buf[80];

	TRACEME(("store_other"));

	/*
	 * Fetch the value from perl only once per store() operation.
	 */

	if (
		forgive_me == 0 ||
		(forgive_me < 0 && !(forgive_me =
			SvTRUE(perl_get_sv("Storable::forgive_me", TRUE)) ? 1 : 0))
	)
		croak("Can't store %s items", sv_reftype(sv, FALSE));

	warn("Can't store %s items", sv_reftype(sv, FALSE));

	/*
	 * Store placeholder string as a scalar instead...
	 */

	(void) sprintf(buf, "You lost %s(0x%lx)\0", sv_reftype(sv, FALSE),
		(unsigned long) sv);

	len = strlen(buf);
	STORE_SCALAR(buf, len);
	TRACEME(("ok (dummy \"%s\", length = %d)", buf, len));

	return 0;
}

/*
 * Dynamic dispatching table for SV store.
 */
static int (*sv_store[])() = {
	store_ref,		/* svis_REF */
	store_scalar,	/* svis_SCALAR */
	store_array,	/* svis_ARRAY */
	store_hash,		/* svis_HASH */
	store_tied,		/* svis_TIED */
	store_other,	/* svis_OTHER */
};

#define SV_STORE(x)	(*sv_store[x])

/*
 * sv_type
 *
 * WARNING: partially duplicates Perl's sv_reftype for speed.
 *
 * Returns the type of the SV, identified by an integer. That integer
 * may then be used to index the dynamic routine dispatch table.
 */
static int sv_type(sv)
SV *sv;
{
	switch (SvTYPE(sv)) {
	case SVt_NULL:
	case SVt_IV:
	case SVt_NV:
		/*
		 * No need to check for ROK, that can't be set here since there
		 * is no field capable of hodling the xrv_rv reference.
		 */
		return svis_SCALAR;
	case SVt_PV:
	case SVt_RV:
	case SVt_PVIV:
	case SVt_PVNV:
		/*
		 * Starting from SVt_PV, it is possible to have the ROK flag
		 * set, the pointer to the other SV being either stored in
		 * the xrv_rv (in the case of a pure SVt_RV), or as the
		 * xpv_pv field of an SVt_PV and its heirs.
		 *
		 * However, those SV cannot be magical or they would be an
		 * SVt_PVMG at least.
		 */
		return SvROK(sv) ? svis_REF : svis_SCALAR;
	case SVt_PVMG:
	case SVt_PVLV:		/* Workaround for perl5.004_04 "LVALUE" bug */
	case SVt_PVBM:
		if (SvRMAGICAL(sv) && (mg_find(sv, 'q')))
			return svis_TIED;
		return SvROK(sv) ? svis_REF : svis_SCALAR;
	case SVt_PVAV:
		if (SvRMAGICAL(sv) && (mg_find(sv, 'P')))
			return svis_TIED;
		return svis_ARRAY;
	case SVt_PVHV:
		if (SvRMAGICAL(sv) && (mg_find(sv, 'P')))
			return svis_TIED;
		return svis_HASH;
	default:
		break;
	}

	return svis_OTHER;
}

/*
 * store
 *
 * Recursively store objects pointed to by the sv to the specified file.
 *
 * Layout is <content> SX_STORED or SX_OBJECT <tagnum> SX_STORED if we
 * reach an already stored object (one for which storage has started--
 * it may not be over if we have a self-referenced structure). This data set
 * forms a stored <object>.
 */
static int store(f, sv)
PerlIO *f;
SV *sv;
{
	dPERINTERP;
	SV **svh;
	int ret;
	int type;
	SV *tag;

	TRACEME(("store (0x%lx)", (unsigned long) sv));

	/*
	 * If object has already been stored, do not duplicate data.
	 * Simply emit the SX_OBJECT marker followed by its tag data.
	 * The tag is always written in network order.
	 *
	 * NOTA BENE, for 64-bit machines: the "*svh" below does not yield a
	 * real pointer, rather a tag number (watch the insertion code below).
	 * That means it pobably safe to assume it is well under the 32-bit limit,
	 * and makes the truncation safe.
	 *		-- RAM, 14/09/1999
	 */

	svh = hv_fetch(hseen, (char *) &sv, sizeof(sv), FALSE);
	if (svh) {
#if PTRSIZE <= 4
		I32 tagval = htonl((I32) (*svh));
#else
		I32 tagval = htonl((I32) ((unsigned long) (*svh) & 0xffffffff));
#endif
		TRACEME(("object 0x%lx seen as #%d.", (unsigned long) sv, tagval));
		PUTMARK(SX_OBJECT);
		WRITE(&tagval, sizeof(I32));
		return 0;
	}

	/*
	 * Allocate a new tag and associate it with the address of the sv being
	 * stored, before recursing...
	 *
	 * In order to avoid creating new SvIVs to hold the tagnum we just
	 * cast the tagnum to a SV pointer and store that in the hash.  This
	 * means that we must clean up the hash manually afterwards, but gives
	 * us a 15% throughput increase.
	 *
	 * The (IV) cast below is for 64-bit machines, to avoid warnings from
	 * the compiler. Please, let me know if it does not work.
	 *		-- RAM, 14/09/1999
	 */

	if (!hv_store(hseen, (char *) &sv, sizeof(sv), (SV*) (IV) (tagnum++), 0))
		return -1;
	TRACEME(("recorded 0x%lx as object #%d", (unsigned long) sv, tagnum));

	/*
	 * Call the proper routine to store this SV.
	 * Abort immediately if we get a non-zero status back.
	 */

	type = sv_type(sv);
	TRACEME(("storing 0x%lx #%d type=%d...", (unsigned long) sv, tagnum, type));
	if (ret = SV_STORE(type)(f, sv))
		return ret;

	/*
	 * If object is blessed, notify the blessing now.
	 *
	 * Since the storable mechanism is going to make usage of lots
	 * of blessed objects (!), we're trying to optimize the cost
	 * by having two separate blessing notifications:
	 *    SX_BLESS <char-len> <class> for short classnames (<255 chars)
	 *    SX_LG_BLESS <int-len> <class> for larger classnames.
	 */

	if (SvOBJECT(sv)) {
		char *class = HvNAME(SvSTASH(sv));
		I32 len = strlen(class);
		unsigned char clen;
		TRACEME(("blessing 0x%lx in %s", (unsigned long) sv, class));
		if (len <= LG_BLESS) {
			PUTMARK(SX_BLESS);
			clen = (unsigned char) len;
			PUTMARK(clen);
		} else {
			PUTMARK(SX_LG_BLESS);
			WLEN(len);
		}
		WRITE(class, len);		/* Final \0 is omitted */
	}

	PUTMARK(SX_STORED);
	TRACEME(("ok (store 0x%lx)", (unsigned long) sv));

	return 0;	/* Done, with success */
}

/*
 * magic_write
 *
 * Write magic number and system information into the file.
 * Layout is <magic> <network> [<len> <byteorder> <sizeof int> <sizeof long>
 * <sizeof ptr>] where <len> is the length of the byteorder hexa string.
 * All size and lenghts are written as single characters here.
 *
 * Note that no byte ordering info is emitted when <network> is true, since
 * integers will be emitted in network order in that case.
 */
static int magic_write(f, use_network_order)
PerlIO *f;
int use_network_order;
{
	dPERINTERP;
	char buf[256];	/* Enough room for 256 hexa digits */
	unsigned char c;

	TRACEME(("magic_write on fd=%d", fileno(f)));

	if (f)
		WRITE(magicstr, strlen(magicstr));	/* Don't write final \0 */

	/*
	 * Starting with 0.6, the "use_network_order" byte flag is also used to
	 * indicate the version number of the binary image, encoded in the upper
	 * bits. The bit 0 is always used to indicate network order.
	 */

	c = (unsigned char)
		((use_network_order ? 0x1 : 0x0) | (STORABLE_BINARY << 1));
	PUTMARK(c);

	if (use_network_order)
		return 0;						/* Don't bother with byte ordering */

	sprintf(buf, "%lx", (unsigned long) BYTEORDER);
	c = (unsigned char) strlen(buf);
	PUTMARK(c);
	WRITE(buf, (unsigned int) c);		/* Don't write final \0 */
	PUTMARK((unsigned char) sizeof(int));
	PUTMARK((unsigned char) sizeof(long));
	PUTMARK((unsigned char) sizeof(char *));

	TRACEME(("ok (magic_write byteorder = 0x%lx [%d], I%d L%d P%d)",
		(unsigned long) BYTEORDER, (int) c,
		sizeof(int), sizeof(long), sizeof(char *)));

	return 0;
}

/*
 * do_store
 *
 * Common code for pstore() and net_pstore().
 */
static int do_store(f, sv, use_network_order)
PerlIO *f;
SV *sv;
int use_network_order;
{
	dPERINTERP;
	int status;

	netorder = use_network_order;	/* Global, not suited for multi-thread */
	forgive_me = -1;				/* Unknown, fetched from perl if needed */
	canonical = -1;					/* Idem */
	tagnum = 0;						/* Reset tag numbers */

	if (-1 == magic_write(f, netorder))	/* Emit magic number and system info */
		return 0;						/* Error */

	/*
	 * Ensure sv is actually a reference. From perl, we called something
	 * like:
	 *       pstore(FILE, \@array);
	 * so we must get the scalar value behing that reference.
	 */

	if (!SvROK(sv))
		croak("Not a reference");
	sv = SvRV(sv);			/* So follow it to know what to store */

	/*
	 * The hash table used to keep track of each SV stored and their
	 * associated tag numbers is special. It is "abused" because the
	 * values stored are not real SV, just integers cast to (SV *),
	 * which explains the freeing below.
	 *
	 * It is also one possible bottlneck to achieve good storing speed,
	 * so the "shared keys" optimization is turned off (unlikely to be
	 * of any use here), and the hash table is "pre-extended". Together,
	 * those optimizations increase the throughput by 12%.
	 */

	hseen = newHV();			/* Table where seen objects are stored */
	HvSHAREKEYS_off(hseen);

	/*
	 * The following does not work well with perl5.004_04, and causes
	 * a core dump later on, in a completely unrelated spot, which
	 * makes me think there is a memory corruption going on.
	 *
	 * Calling hv_ksplit(hseen, HBUCKETS) instead of manually hacking
	 * it below does not make any difference. It seems to work fine
	 * with perl5.004_68 but given the probable nature of the bug,
	 * that does not prove anything.
	 *
	 * It's a shame because increasing the amount of buckets raises
	 * store() throughput by 5%, but until I figure this out, I can't
	 * allow for this to go into production.
	 */
#if 0
#define HBUCKETS	4096			/* Buckets for %hseen */
	HvMAX(hseen) = HBUCKETS - 1;	/* keys %hseen = $HBUCKETS; */
#endif

	/*
	 * Recursively store object...
	 */

	status = store(f, sv);		/* Just do it! */

	/*
	 * Need to free the hseen table, but since we have stored fake
	 * value pointers in it, we need to make them real first.
	 */

	{
		HE * he;

		hv_iterinit(hseen);
		while (he = hv_iternext(hseen))
			HeVAL(he) = &PL_sv_undef;
	}
	hv_undef(hseen);		/* Free seen object table */
	sv_free((SV *) hseen);	/* Free HV */

	TRACEME(("do_store returns %d", status));

	return status == 0;
}

/*
 * mbuf2sv
 *
 * Build a new SV out of the content of the internal memory buffer.
 */
static SV *mbuf2sv()
{
	dPERINTERP;
	return newSVpv(mbase, MBUF_SIZE());
}

/*
 * mstore
 *
 * Store the transitive data closure of given object to memory.
 * Returns undef on error, a scalar value containing the data otherwise.
 */
SV *mstore(sv)
SV *sv;
{
	dPERINTERP;
	TRACEME(("mstore"));
	MBUF_INIT(0);
	if (!do_store(0, sv, FALSE))		/* Not in network order */
		return &PL_sv_undef;

	return mbuf2sv();
}

/*
 * net_mstore
 *
 * Same as mstore(), but network order is used for integers and doubles are
 * emitted as strings.
 */
SV *net_mstore(sv)
SV *sv;
{
	dPERINTERP;
	TRACEME(("net_mstore"));
	MBUF_INIT(0);
	if (!do_store(0, sv, TRUE))	/* Use network order */
		return &PL_sv_undef;

	return mbuf2sv();
}

/*
 * pstore
 *
 * Store the transitive data closure of given object to disk.
 * Returns 0 on error, a true value otherwise.
 */
int pstore(f, sv)
PerlIO *f;
SV *sv;
{
	TRACEME(("pstore"));
	return do_store(f, sv, FALSE);	/* Not in network order */

}

/*
 * net_pstore
 *
 * Same as pstore(), but network order is used for integers and doubles are
 * emitted as strings.
 */
int net_pstore(f, sv)
PerlIO *f;
SV *sv;
{
	TRACEME(("net_pstore"));
	return do_store(f, sv, TRUE);			/* Use network order */
}

/*
 * retrieve_ref
 *
 * Retrieve reference to some other scalar.
 * Layout is SX_REF <object>, with SX_REF already read.
 */
static SV *retrieve_ref(f)
PerlIO *f;
{
	dPERINTERP;
	SV *rv;
	SV *sv;

	TRACEME(("retrieve_ref (#%d)", tagnum));

	/*
	 * We need to create the SV that holds the reference to the yet-to-retrieve
	 * object now, so that we may record the address in the seen table.
	 * Otherwise, if the object to retrieve references us, we won't be able
	 * to resolve the SX_OBJECT we'll see at that point! Hence we cannot
	 * do the retrieve first and use rv = newRV(sv) since it will be too late
	 * for SEEN() recording.
	 */

	rv = NEWSV(10002, 0);
	SEEN(rv);				/* Will return if rv is null */
	sv = retrieve(f);		/* Retrieve <object> */
	if (!sv)
		return (SV *) 0;	/* Failed */

	/*
	 * WARNING: breaks RV encapsulation.
	 *
	 * Now for the tricky part. We have to upgrade our existing SV, so that
	 * it is now an RV on sv... Again, we cheat by duplicating the code
	 * held in newSVrv(), since we already got our SV from retrieve().
	 *
	 * We don't say:
	 *
	 *		SvRV(rv) = SvREFCNT_inc(sv);
	 *
	 * here because the reference count we got from retrieve() above is
	 * already correct: if the object was retrieved from the file, then
	 * its reference count is one. Otherwise, if it was retrieved via
	 * an SX_OBJECT indication, a ref count increment was done.
	 */

	sv_upgrade(rv, SVt_RV);
	SvRV(rv) = sv;				/* $rv = \$sv */
	SvROK_on(rv);

	TRACEME(("ok (retrieve_ref at 0x%lx)", (unsigned long) rv));

	return rv;
}

/*
 * retrieve_tied_array
 *
 * Retrieve tied array
 * Layout is SX_TIED_ARRAY <object>, with SX_TIED_ARRAY already read.
 */
static SV *retrieve_tied_array(f)
PerlIO *f;
{
	dPERINTERP;
	SV *tv;
	SV *sv;

	TRACEME(("retrieve_tied_array (#%d)", tagnum));

	tv = NEWSV(10002, 0);
	SEEN(tv);					/* Will return if tv is null */
	sv = retrieve(f);			/* Retrieve <object> */
	if (!sv)
		return (SV *) 0;		/* Failed */

	sv_upgrade(tv, SVt_PVAV);
	AvREAL_off((AV *)tv);
	sv_magic(tv, sv, 'P', Nullch, 0);
	SvREFCNT_dec(sv);			/* Undo refcnt inc from sv_magic() */

	TRACEME(("ok (retrieve_tied_array at 0x%lx)", (unsigned long) tv));

	return tv;
}

/*
 * retrieve_tied_hash
 *
 * Retrieve tied hash
 * Layout is SX_TIED_HASH <object>, with SX_TIED_HASH already read.
 */
static SV *retrieve_tied_hash(f)
PerlIO *f;
{
	dPERINTERP;
	SV *tv;
	SV *sv;

	TRACEME(("retrieve_tied_hash (#%d)", tagnum));

	tv = NEWSV(10002, 0);
	SEEN(tv);					/* Will return if rv is null */
	sv = retrieve(f);			/* Retrieve <object> */
	if (!sv)
		return (SV *) 0;		/* Failed */

	sv_upgrade(tv, SVt_PVHV);
	sv_magic(tv, sv, 'P', Nullch, 0);
	SvREFCNT_dec(sv);			/* Undo refcnt inc from sv_magic() */

	TRACEME(("ok (retrieve_tied_hash at 0x%lx)", (unsigned long) tv));

	return tv;
}

/*
 * retrieve_tied_scalar
 *
 * Retrieve tied scalar
 * Layout is SX_TIED_SCALAR <object>, with SX_TIED_SCALAR already read.
 */
static SV *retrieve_tied_scalar(f)
PerlIO *f;
{
	dPERINTERP;
	SV *tv;
	SV *sv;

	TRACEME(("retrieve_tied_scalar (#%d)", tagnum));

	tv = NEWSV(10002, 0);
	SEEN(tv);					/* Will return if rv is null */
	sv = retrieve(f);			/* Retrieve <object> */
	if (!sv)
		return (SV *) 0;		/* Failed */

	sv_upgrade(tv, SVt_PVMG);
	sv_magic(tv, sv, 'q', Nullch, 0);
	SvREFCNT_dec(sv);			/* Undo refcnt inc from sv_magic() */

	TRACEME(("ok (retrieve_tied_scalar at 0x%lx)", (unsigned long) tv));

	return tv;
}

/*
 * retrieve_lscalar
 *
 * Retrieve defined long (string) scalar.
 *
 * Layout is SX_LSCALAR <length> <data>, with SX_LSCALAR already read.
 * The scalar is "long" in that <length> is larger than LG_SCALAR so it
 * was not stored on a single byte.
 */
static SV *retrieve_lscalar(f)
PerlIO *f;
{
	dPERINTERP;
	STRLEN len;
	SV *sv;

	RLEN(len);
	TRACEME(("retrieve_lscalar (#%d), len = %d", tagnum, len));

	/*
	 * Allocate an empty scalar of the suitable length.
	 */

	sv = NEWSV(10002, len);
	SEEN(sv);			/* Associate this new scalar with tag "tagnum" */

	/*
	 * WARNING: duplicates parts of sv_setpv and breaks SV data encapsulation.
	 *
	 * Now, for efficiency reasons, read data directly inside the SV buffer,
	 * and perform the SV final settings directly by duplicating the final
	 * work done by sv_setpv. Since we're going to allocate lots of scalars
	 * this way, it's worth the hassle and risk.
	 */

	SAFEREAD(SvPVX(sv), len, sv);
	SvCUR_set(sv, len);				/* Record C string length */
	*SvEND(sv) = '\0';				/* Ensure it's null terminated anyway */
	(void) SvPOK_only(sv);			/* Validate string pointer */
	SvTAINT(sv);					/* External data cannot be trusted */

	TRACEME(("large scalar len %d '%s'", len, SvPVX(sv)));
	TRACEME(("ok (retrieve_lscalar at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_scalar
 *
 * Retrieve defined short (string) scalar.
 *
 * Layout is SX_SCALAR <length> <data>, with SX_SCALAR already read.
 * The scalar is "short" so <length> is single byte. If it is 0, there
 * is no <data> section.
 */
static SV *retrieve_scalar(f)
PerlIO *f;
{
	dPERINTERP;
	int len;
	SV *sv;

	GETMARK(len);
	TRACEME(("retrieve_scalar (#%d), len = %d", tagnum, len));

	/*
	 * Allocate an empty scalar of the suitable length.
	 */

	sv = NEWSV(10002, len);
	SEEN(sv);			/* Associate this new scalar with tag "tagnum" */

	/*
	 * WARNING: duplicates parts of sv_setpv and breaks SV data encapsulation.
	 */

	if (len == 0) {
		/*
		 * newSV did not upgrade to SVt_PV so the scalar is undefined.
		 * To make it defined with an empty length, upgrade it now...
		 */
		sv_upgrade(sv, SVt_PV);
		SvGROW(sv, 1);
		*SvEND(sv) = '\0';			/* Ensure it's null terminated anyway */
		TRACEME(("ok (retrieve_scalar empty at 0x%lx)", (unsigned long) sv));
	} else {
		/*
		 * Now, for efficiency reasons, read data directly inside the SV buffer,
		 * and perform the SV final settings directly by duplicating the final
		 * work done by sv_setpv. Since we're going to allocate lots of scalars
		 * this way, it's worth the hassle and risk.
		 */
		SAFEREAD(SvPVX(sv), len, sv);
		SvCUR_set(sv, len);			/* Record C string length */
		*SvEND(sv) = '\0';			/* Ensure it's null terminated anyway */
		TRACEME(("small scalar len %d '%s'", len, SvPVX(sv)));
	}

	(void) SvPOK_only(sv);			/* Validate string pointer */
	SvTAINT(sv);					/* External data cannot be trusted */

	TRACEME(("ok (retrieve_scalar at 0x%lx)", (unsigned long) sv));
	return sv;
}

/*
 * retrieve_integer
 *
 * Retrieve defined integer.
 * Layout is SX_INTEGER <data>, whith SX_INTEGER already read.
 */
static SV *retrieve_integer(f)
PerlIO *f;
{
	dPERINTERP;
	SV *sv;
	IV iv;

	TRACEME(("retrieve_integer (#%d)", tagnum));

	READ(&iv, sizeof(iv));
	sv = newSViv(iv);
	SEEN(sv);			/* Associate this new scalar with tag "tagnum" */

	TRACEME(("integer %d", iv));
	TRACEME(("ok (retrieve_integer at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_netint
 *
 * Retrieve defined integer in network order.
 * Layout is SX_NETINT <data>, whith SX_NETINT already read.
 */
static SV *retrieve_netint(f)
PerlIO *f;
{
	dPERINTERP;
	SV *sv;
	int iv;

	TRACEME(("retrieve_netint (#%d)", tagnum));

	READ(&iv, sizeof(iv));
#ifdef HAS_NTOHL
	sv = newSViv((int) ntohl(iv));
	TRACEME(("network integer %d", (int) ntohl(iv)));
#else
	sv = newSViv(iv);
	TRACEME(("network integer (as-is) %d", iv));
#endif
	SEEN(sv);			/* Associate this new scalar with tag "tagnum" */

	TRACEME(("ok (retrieve_netint at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_double
 *
 * Retrieve defined double.
 * Layout is SX_DOUBLE <data>, whith SX_DOUBLE already read.
 */
static SV *retrieve_double(f)
PerlIO *f;
{
	dPERINTERP;
	SV *sv;
	double nv;

	TRACEME(("retrieve_double (#%d)", tagnum));

	READ(&nv, sizeof(nv));
	sv = newSVnv(nv);
	SEEN(sv);			/* Associate this new scalar with tag "tagnum" */

	TRACEME(("double %lf", nv));
	TRACEME(("ok (retrieve_double at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_byte
 *
 * Retrieve defined byte (small integer within the [-128, +127] range).
 * Layout is SX_BYTE <data>, whith SX_BYTE already read.
 */
static SV *retrieve_byte(f)
PerlIO *f;
{
	dPERINTERP;
	SV *sv;
	int siv;

	TRACEME(("retrieve_byte (#%d)", tagnum));

	GETMARK(siv);
	TRACEME(("small integer read as %d", (unsigned char) siv));
	sv = newSViv((unsigned char) siv - 128);
	SEEN(sv);			/* Associate this new scalar with tag "tagnum" */

	TRACEME(("byte %d", (unsigned char) siv - 128));
	TRACEME(("ok (retrieve_byte at 0x%lx)", (unsigned long) sv));

	return sv;
}

/*
 * retrieve_undef
 *
 * Return the undefined value.
 */
static SV *retrieve_undef()
{
	dPERINTERP;
	SV* sv;

	TRACEME(("retrieve_undef"));

	sv = newSV(0);
	SEEN(sv);

	return sv;
}

/*
 * retrieve_sv_undef
 *
 * Return the immortal undefined value.
 */
static SV *retrieve_sv_undef()
{
	dPERINTERP;
	SV *sv = &PL_sv_undef;

	TRACEME(("retrieve_sv_undef"));

	SEEN(sv);
	return sv;
}

/*
 * retrieve_sv_yes
 *
 * Return the immortal yes value.
 */
static SV *retrieve_sv_yes()
{
	dPERINTERP;
	SV *sv = &PL_sv_yes;

	TRACEME(("retrieve_sv_yes"));

	SEEN(sv);
	return sv;
}

/*
 * retrieve_sv_no
 *
 * Return the immortal no value.
 */
static SV *retrieve_sv_no()
{
	dPERINTERP;
	SV *sv = &PL_sv_no;

	TRACEME(("retrieve_sv_no"));

	SEEN(sv);
	return sv;
}

/*
 * retrieve_other
 *
 * Return an error via croak, since it is not possible that we get here
 * under normal conditions, when facing a file produced via pstore().
 */
static SV *retrieve_other()
{
	croak("Corrupted perl storable file");
	return (SV *) 0;
}

/*
 * retrieve_array
 *
 * Retrieve a whole array.
 * Layout is SX_ARRAY <size> followed by each item, in increading index order.
 * Each item is stored as <object>.
 *
 * When we come here, SX_ARRAY has been read already.
 */
static SV *retrieve_array(f)
PerlIO *f;
{
	dPERINTERP;
	I32 len;
	I32 i;
	AV *av;
	SV *sv;

	TRACEME(("retrieve_array (#%d)", tagnum));

	/*
	 * Read length, and allocate array, then pre-extend it.
	 */

	RLEN(len);
	TRACEME(("size = %d", len));
	av = newAV();
	SEEN(av);					/* Will return if array not allocated nicely */
	if (len)
		av_extend(av, len);
	else
		return (SV *) av;		/* No data follow if array is empty */

	/*
	 * Now get each item in turn...
	 */

	for (i = 0; i < len; i++) {
		TRACEME(("(#%d) item", i));
		sv = retrieve(f);				/* Retrieve item */
		if (!sv)
			return (SV *) 0;
		if (av_store(av, i, sv) == 0)
			return (SV *) 0;
	}

	TRACEME(("ok (retrieve_array at 0x%lx)", (unsigned long) av));

	return (SV *) av;
}

/*
 * retrieve_hash
 *
 * Retrieve a whole hash table.
 * Layout is SX_HASH <size> followed by each key/value pair, in random order.
 * Keys are stored as <length> <data>, the <data> section being omitted
 * if length is 0.
 * Values are stored as <object>.
 *
 * When we come here, SX_HASH has been read already.
 */
static SV *retrieve_hash(f)
PerlIO *f;
{
	dPERINTERP;
	I32 len;
	I32 size;
	I32 i;
	HV *hv;
	SV *sv;
	static SV *sv_h_undef = (SV *) 0;		/* hv_store() bug */

	TRACEME(("retrieve_hash (#%d)", tagnum));

	/*
	 * Read length, allocate table.
	 */

	RLEN(len);
	TRACEME(("size = %d", len));
	hv = newHV();
	SEEN(hv);			/* Will return if table not allocated properly */
	if (len == 0)
		return (SV *) hv;	/* No data follow if table empty */

	/*
	 * Now get each key/value pair in turn...
	 */

	for (i = 0; i < len; i++) {
		/*
		 * Get value first.
		 */

		TRACEME(("(#%d) value", i));
		sv = retrieve(f);
		if (!sv)
			return (SV *) 0;

		/*
		 * Get key.
		 * Since we're reading into kbuf, we must ensure we're not
		 * recursing between the read and the hv_store() where it's used.
		 * Hence the key comes after the value.
		 */

		RLEN(size);						/* Get key size */
		KBUFCHK(size);					/* Grow hash key read pool if needed */
		if (size)
			READ(kbuf, size);
		kbuf[size] = '\0';				/* Mark string end, just in case */
		TRACEME(("(#%d) key '%s'", i, kbuf));

		/*
		 * Enter key/value pair into hash table.
		 */

		if (hv_store(hv, kbuf, (U32) size, sv, 0) == 0)
			return (SV *) 0;
	}

	TRACEME(("ok (retrieve_hash at 0x%lx)", (unsigned long) hv));

	return (SV *) hv;
}

/*
 * old_retrieve_array
 *
 * Retrieve a whole array in pre-0.6 binary format.
 *
 * Layout is SX_ARRAY <size> followed by each item, in increading index order.
 * Each item is stored as SX_ITEM <object> or SX_IT_UNDEF for "holes".
 *
 * When we come here, SX_ARRAY has been read already.
 */
static SV *old_retrieve_array(f)
PerlIO *f;
{
	dPERINTERP;
	I32 len;
	I32 i;
	AV *av;
	SV *sv;
	int c;

	TRACEME(("old_retrieve_array (#%d)", tagnum));

	/*
	 * Read length, and allocate array, then pre-extend it.
	 */

	RLEN(len);
	TRACEME(("size = %d", len));
	av = newAV();
	SEEN(av);					/* Will return if array not allocated nicely */
	if (len)
		av_extend(av, len);
	else
		return (SV *) av;		/* No data follow if array is empty */

	/*
	 * Now get each item in turn...
	 */

	for (i = 0; i < len; i++) {
		GETMARK(c);
		if (c == SX_IT_UNDEF) {
			TRACEME(("(#%d) undef item", i));
			continue;			/* av_extend() already filled us with undef */
		}
		if (c != SX_ITEM)
			(void) retrieve_other();	/* Will croak out */
		TRACEME(("(#%d) item", i));
		sv = retrieve(f);				/* Retrieve item */
		if (!sv)
			return (SV *) 0;
		if (av_store(av, i, sv) == 0)
			return (SV *) 0;
	}

	TRACEME(("ok (old_retrieve_array at 0x%lx)", (unsigned long) av));

	return (SV *) av;
}

/*
 * old_retrieve_hash
 *
 * Retrieve a whole hash table in pre-0.6 binary format.
 *
 * Layout is SX_HASH <size> followed by each key/value pair, in random order.
 * Keys are stored as SX_KEY <length> <data>, the <data> section being omitted
 * if length is 0.
 * Values are stored as SX_VALUE <object> or SX_VL_UNDEF for "holes".
 *
 * When we come here, SX_HASH has been read already.
 */
static SV *old_retrieve_hash(f)
PerlIO *f;
{
	dPERINTERP;
	I32 len;
	I32 size;
	I32 i;
	HV *hv;
	SV *sv;
	int c;
	static SV *sv_h_undef = (SV *) 0;		/* hv_store() bug */

	TRACEME(("old_retrieve_hash (#%d)", tagnum));

	/*
	 * Read length, allocate table.
	 */

	RLEN(len);
	TRACEME(("size = %d", len));
	hv = newHV();
	SEEN(hv);				/* Will return if table not allocated properly */
	if (len == 0)
		return (SV *) hv;	/* No data follow if table empty */

	/*
	 * Now get each key/value pair in turn...
	 */

	for (i = 0; i < len; i++) {
		/*
		 * Get value first.
		 */

		GETMARK(c);
		if (c == SX_VL_UNDEF) {
			TRACEME(("(#%d) undef value", i));
			/*
			 * Due to a bug in hv_store(), it's not possible to pass
			 * &PL_sv_undef to hv_store() as a value, otherwise the
			 * associated key will not be creatable any more. -- RAM, 14/01/97
			 */
			if (!sv_h_undef)
				sv_h_undef = newSVsv(&PL_sv_undef);
			sv = SvREFCNT_inc(sv_h_undef);
		} else if (c == SX_VALUE) {
			TRACEME(("(#%d) value", i));
			sv = retrieve(f);
			if (!sv)
				return (SV *) 0;
		} else
			(void) retrieve_other();	/* Will croak out */

		/*
		 * Get key.
		 * Since we're reading into kbuf, we must ensure we're not
		 * recursing between the read and the hv_store() where it's used.
		 * Hence the key comes after the value.
		 */

		GETMARK(c);
		if (c != SX_KEY)
			(void) retrieve_other();	/* Will croak out */
		RLEN(size);						/* Get key size */
		KBUFCHK(size);					/* Grow hash key read pool if needed */
		if (size)
			READ(kbuf, size);
		kbuf[size] = '\0';				/* Mark string end, just in case */
		TRACEME(("(#%d) key '%s'", i, kbuf));

		/*
		 * Enter key/value pair into hash table.
		 */

		if (hv_store(hv, kbuf, (U32) size, sv, 0) == 0)
			return (SV *) 0;
	}

	TRACEME(("ok (retrieve_hash at 0x%lx)", (unsigned long) hv));

	return (SV *) hv;
}

/*
 * Dynamic dispatching tables for SV retrieval.
 */

static SV *(*sv_old_retrieve[])() = {
	0,						/* SX_OBJECT -- entry unused dynamically */
	retrieve_lscalar,		/* SX_LSCALAR */
	old_retrieve_array,		/* SX_ARRAY -- for pre-0.6 binaries */
	old_retrieve_hash,		/* SX_HASH -- for pre-0.6 binaries */
	retrieve_ref,			/* SX_REF */
	retrieve_undef,			/* SX_UNDEF */
	retrieve_integer,		/* SX_INTEGER */
	retrieve_double,		/* SX_DOUBLE */
	retrieve_byte,			/* SX_BYTE */
	retrieve_netint,		/* SX_NETINT */
	retrieve_scalar,		/* SX_SCALAR */
	retrieve_tied_array,	/* SX_ARRAY */
	retrieve_tied_hash,		/* SX_HASH */
	retrieve_tied_scalar,	/* SX_SCALAR */
	retrieve_other,			/* SX_SV_UNDEF not supported */
	retrieve_other,			/* SX_SV_YES not supported */
	retrieve_other,			/* SX_SV_NO not supported */
	retrieve_other,			/* SX_ERROR */
};

static SV *(*sv_retrieve[])() = {
	0,						/* SX_OBJECT -- entry unused dynamically */
	retrieve_lscalar,		/* SX_LSCALAR */
	retrieve_array,			/* SX_ARRAY */
	retrieve_hash,			/* SX_HASH */
	retrieve_ref,			/* SX_REF */
	retrieve_undef,			/* SX_UNDEF */
	retrieve_integer,		/* SX_INTEGER */
	retrieve_double,		/* SX_DOUBLE */
	retrieve_byte,			/* SX_BYTE */
	retrieve_netint,		/* SX_NETINT */
	retrieve_scalar,		/* SX_SCALAR */
	retrieve_tied_array,	/* SX_ARRAY */
	retrieve_tied_hash,		/* SX_HASH */
	retrieve_tied_scalar,	/* SX_SCALAR */
	retrieve_sv_undef,		/* SX_SV_UNDEF */
	retrieve_sv_yes,		/* SX_SV_YES */
	retrieve_sv_no,			/* SX_SV_NO */
	retrieve_other,			/* SX_ERROR */
};

static SV *(**sv_retrieve_vtbl)();	/* One of the above -- XXX for threads */

#define RETRIEVE(x)	(*sv_retrieve_vtbl[(x) >= SX_ERROR ? SX_ERROR : (x)])

/*
 * magic_check
 *
 * Make sure the stored data we're trying to retrieve has been produced
 * on an ILP compatible system with the same byteorder. It croaks out in
 * case an error is detected. [ILP = integer-long-pointer sizes]
 * Returns null if error is detected, &PL_sv_undef otherwise.
 *
 * Note that there's no byte ordering info emitted when network order was
 * used at store time.
 */
static SV *magic_check(f)
PerlIO *f;
{
	dPERINTERP;
	char buf[256];
	char byteorder[256];
	int c;
	int use_network_order;
	int version;

	/*
	 * The "magic number" is only for files, not when freezing in memory.
	 */

	if (f) {
		STRLEN len = sizeof(magicstr) - 1;
		STRLEN old_len;

		READ(buf, len);					/* Not null-terminated */
		buf[len] = '\0';				/* Is now */

		if (0 == strcmp(buf, magicstr))
			goto magic_ok;

		/*
		 * Try to read more bytes to check for the old magic number, which
		 * was longer.
		 */

		old_len = sizeof(old_magicstr) - 1;
		READ(&buf[len], old_len - len);
		buf[old_len] = '\0';			/* Is now null-terminated */

		if (strcmp(buf, old_magicstr))
			croak("File is not a perl storable");
	}

magic_ok:
	/*
	 * Starting with 0.6, the "use_network_order" byte flag is also used to
	 * indicate the version number of the binary, and therefore governs the
	 * setting of sv_retrieve_vtbl. See magic_write().
	 */

	GETMARK(use_network_order);
	version = use_network_order >> 1;
	sv_retrieve_vtbl = version ? sv_retrieve : sv_old_retrieve;
	TRACEME(("binary image version is %d", version));

	if (netorder = (use_network_order & 0x1))
		return &PL_sv_undef;			/* No byte ordering info */

	sprintf(byteorder, "%lx", (unsigned long) BYTEORDER);
	GETMARK(c);
	READ(buf, c);						/* Not null-terminated */
	buf[c] = '\0';						/* Is now */

	if (strcmp(buf, byteorder))
		croak("Byte order is not compatible");
	
	GETMARK(c);		/* sizeof(int) */
	if ((int) c != sizeof(int))
		croak("Integer size is not compatible");

	GETMARK(c);		/* sizeof(long) */
	if ((int) c != sizeof(long))
		croak("Long integer size is not compatible");

	GETMARK(c);		/* sizeof(char *) */
	if ((int) c != sizeof(char *))
		croak("Pointer integer size is not compatible");

	return &PL_sv_undef;	/* OK */
}

/*
 * retrieve
 *
 * Recursively retrieve objects from the specified file and return their
 * root SV (which may be an AV or an HV for what we care).
 * Returns null if there is a problem.
 */
static SV *retrieve(f)
PerlIO *f;
{
	dPERINTERP;
	int type;
	SV **svh;
	SV *sv;

	TRACEME(("retrieve"));

	/*
	 * Grab address tag which identifies the object if we are retrieving
	 * an older format. Since the new binary format counts objects and no
	 * longer explicitely tags them, we must keep track of the correspondance
	 * ourselves.
	 *
	 * The following section will disappear one day when the old format is
	 * no longer supported, hence the final "goto" in the "if" block.
	 */

	if (hseen) {							/* Retrieving old binary */
		stag_t tag;
		if (netorder) {
			I32 nettag;
			READ(&nettag, sizeof(I32));		/* Ordered sequence of I32 */
			tag = (stag_t) nettag;
		} else
			READ(&tag, sizeof(stag_t));		/* Original address of the SV */

		GETMARK(type);
		if (type == SX_OBJECT) {
			I32 tagn;
			svh = hv_fetch(hseen, (char *) &tag, sizeof(tag), FALSE);
			if (!svh)
				croak("Old tag 0x%x should have been mapped already", tag);
			tagn = SvIV(*svh);	/* Mapped tag number computed earlier below */

			/*
			 * The following code is common with the SX_OBJECT case below.
			 */

			svh = av_fetch(aseen, tagn, FALSE);
			if (!svh)
				croak("Object #%d should have been retrieved already", tagn);
			sv = *svh;
			TRACEME(("already retrieved at 0x%lx", (unsigned long) sv));
			SvREFCNT_inc(sv);	/* One more reference to this same sv */
			return sv;			/* The SV pointer where object was retrieved */
		}

		/*
		 * Map new object, but don't increase tagnum. This will be done
		 * by each of the retrieve_* functions when they call SEEN().
		 *
		 * The mapping associates the "tag" initially present with a unique
		 * tag number. See test for SX_OBJECT above to see how this is perused.
		 */

		if (!hv_store(hseen, (char *) &tag, sizeof(tag), newSViv(tagnum), 0))
			return (SV *) 0;

		goto first_time;
	}

	/*
	 * Regular post-0.6 binary format.
	 */

	GETMARK(type);

	TRACEME(("retrieve type = %d", type));

	/*
	 * If the object type is SX_OBJECT, then we're dealing with an object we
	 * should have already retrieved. Otherwise, we've got a new one....
	 */

	if (type == SX_OBJECT) {
		I32 tag;
		READ(&tag, sizeof(I32));
		tag = ntohl(tag);
		svh = av_fetch(aseen, tag, FALSE);
		if (!svh)
			croak("Object #%d should have been retrieved already", tag);
		sv = *svh;
		TRACEME(("already retrieved at 0x%lx", (unsigned long) sv));
		SvREFCNT_inc(sv);	/* One more reference to this same sv */
		return sv;			/* The SV pointer where object was retrieved */
	}

first_time:		/* Will disappear when support for old format is dropped */

	/*
	 * Okay, first time through for this one.
	 */

	sv = RETRIEVE(type)(f);
	if (!sv)
		return (SV *) 0;			/* Failed */

	/*
	 * Final notifications, ended by SX_STORED may now follow.
	 * Currently, the only pertinent notification to apply on the
	 * freshly retrieved object is either:
	 *    SX_BLESS <char-len> <classname> for short classnames.
	 *    SX_LG_BLESS <int-len> <classname> for larger one (rare!).
	 * Class name is then read into the key buffer pool used by
	 * hash table key retrieval.
	 */

	while ((type = GETCHAR()) != SX_STORED) {
		I32 len;
		HV *stash;
		SV *ref;
		switch (type) {
		case SX_BLESS:
			GETMARK(len);			/* Length coded on a single char */
			break;
		case SX_LG_BLESS:			/* Length coded on a regular integer */
			RLEN(len);
			break;
		case EOF:
		default:
			return (SV *) 0;		/* Failed */
		}
		KBUFCHK(len);				/* Grow buffer as necessary */
		if (len)
			READ(kbuf, len);
		kbuf[len] = '\0';			/* Mark string end */
		TRACEME(("blessing 0x%lx in %s", (unsigned long) sv, kbuf));
		stash = gv_stashpv(kbuf, TRUE);
		ref = newRV_noinc(sv);		/* To please sv_bless() */
		(void) sv_bless(ref, stash);
		SvRV(ref) = 0;
		SvREFCNT_dec(ref);			/* Reclaim temporary reference */
	}

	TRACEME(("ok (retrieved 0x%lx, refcnt=%d, %s)", (unsigned long) sv,
		SvREFCNT(sv) - 1, sv_reftype(sv, FALSE)));

	return sv;	/* Ok */
}

/*
 * do_retrieve
 *
 * Retrieve data held in file and return the root object.
 * Common routine for pretrieve and mretrieve.
 */
static SV *do_retrieve(f)
PerlIO *f;
{
	dPERINTERP;
	SV *sv;

	TRACEME(("do_retrieve"));
	KBUFINIT();			 	/* Allocate hash key reading pool once */

	/*
	 * Magic number verifications.
	 */

	if (!magic_check(f))
		croak("Magic number checking on perl storable failed");

	TRACEME(("data stored in %s format", netorder ? "net order" : "native"));

	/*
	 * If retrieving an old binary version, the sv_retrieve_vtbl variable is
	 * set to sv_old_retrieve. We'll need a hash table to keep track of
	 * the correspondance between the tags and the tag number used by the
	 * new retrieve routines.
	 */

	hseen = (sv_retrieve_vtbl == sv_old_retrieve) ? newHV() : 0;

	aseen = newAV();		/* Table where retrieved objects are kept */
	tagnum = 0;				/* Have to count objects too */
	sv = retrieve(f);		/* Recursively retrieve object, get root SV */
	av_undef(aseen);		/* Free retrieved object table */
	sv_free((SV *) aseen);	/* Free AV */

	if (hseen)
		sv_free((SV *) hseen);	/* Free HV if created above */

	if (!sv) {
		TRACEME(("retrieve ERROR"));
		return &PL_sv_undef;	/* Something went wrong, return undef */
	}

	TRACEME(("retrieve got %s(0x%lx)",
		sv_reftype(sv, FALSE), (unsigned long) sv));

	/*
	 * Build a reference to the SV returned by pretrieve even if it is
	 * already one and not a scalar, for consistency reasons.
	 *
	 * Backward compatibility with Storable-0.5@9 (which we know we
	 * are retrieving if hseen is non-null): don't create an extra RV
	 * for objects since we special-cased it at store time.
	 */

	if (hseen) {
		SV *rv;
		if (sv_type(sv) == svis_REF && (rv = SvRV(sv)) && SvOBJECT(rv))
			return sv;
	}

	return newRV_noinc(sv);
}

/*
 * pretrieve
 *
 * Retrieve data held in file and return the root object, undef on error.
 */
SV *pretrieve(f)
PerlIO *f;
{
	TRACEME(("pretrieve"));
	return do_retrieve(f);
}

/*
 * mretrieve
 *
 * Retrieve data held in scalar and return the root object, undef on error.
 */
SV *mretrieve(sv)
SV *sv;
{
	dPERINTERP;
	struct extendable mcommon;			/* Temporary save area for global */
	SV *rsv;							/* Retrieved SV pointer */

	TRACEME(("mretrieve"));
	StructCopy(&membuf, &mcommon, struct extendable);

	MBUF_LOAD(sv);
	rsv = do_retrieve(0);

	StructCopy(&mcommon, &membuf, struct extendable);
	return rsv;
}

/*
 * dclone
 *
 * Deep clone: returns a fresh copy of the original referenced SV tree.
 *
 * This is achieved by storing the object in memory and restoring from
 * there. Not that efficient, but it should be faster than doing it from
 * pure perl anyway.
 */
SV *dclone(sv)
SV *sv;
{
	dPERINTERP;
	int size;

	TRACEME(("dclone"));

	MBUF_INIT(0);
	if (!do_store(0, sv, FALSE))		/* Not in network order! */
		return &PL_sv_undef;			/* Error during store */

	size = MBUF_SIZE();
	TRACEME(("dclone stored %d bytes", size));

	MBUF_INIT(size);
	return do_retrieve(0);
}

/*
 * last_op_in_netorder
 *
 * Returns whether last operation was made using network order.
 *
 * This is typically out-of-band information that might prove useful
 * to people wishing to convert native to network order data when used.
 */
int last_op_in_netorder()
{
	dPERINTERP;

	return netorder;
}

/*
 * init_perinterp
 *
 * Called once per "thread" (interpreter) to initialize some global context.
 */
static void init_perinterp() {
    INIT_PERINTERP;
    netorder = 0;	/* true if network order used */
    forgive_me = -1;	/* whether to be forgiving... */
}

/*
 * The Perl IO GV object distinguishes between input and output for sockets
 * but not for plain files. To allow Storable to transparently work on
 * plain files and sockets transparently, we have to ask xsubpp to fetch the
 * right object for us. Hence the OutputStream and InputStream declarations.
 *
 * Before perl 5.004_05, those entries in the standard typemap are not
 * defined in perl include files, so we do that here.
 */

#ifndef OutputStream
#define OutputStream	PerlIO *
#define InputStream		PerlIO *
#endif	/* !OutputStream */

MODULE = Storable	PACKAGE = Storable

PROTOTYPES: ENABLE

BOOT:
    init_perinterp();

int
pstore(f,obj)
OutputStream	f
SV *	obj

int
net_pstore(f,obj)
OutputStream	f
SV *	obj

SV *
mstore(obj)
SV *	obj

SV *
net_mstore(obj)
SV *	obj

SV *
pretrieve(f)
InputStream	f

SV *
mretrieve(sv)
SV *	sv

SV *
dclone(sv)
SV *	sv

int
last_op_in_netorder()

