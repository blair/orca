#include "util.h"

/*
=for apidoc scan_version

Returns a pointer to the next character after the parsed
version string, as well as upgrading the passed in SV to
an RV.

Function must be called with an already existing SV like

    sv = newSV(0);
    s = scan_version(s,SV *sv, bool qv);

Performs some preprocessing to the string to ensure that
it has the correct characteristics of a version.  Flags the
object if it contains an underscore (which denotes this
is a alpha version).  The boolean qv denotes that the version
should be interpreted as if it had multiple decimals, even if
it doesn't.

=cut
*/

char *
Perl_scan_version(pTHX_ char *s, SV *rv, bool qv)
{
    const char *start = s;
    char *pos = s;
    I32 saw_period = 0;
    bool saw_under = 0;
    SV* sv = newSVrv(rv, "version"); /* create an SV and upgrade the RV */
    (void)sv_upgrade(sv, SVt_PVAV); /* needs to be an AV type */

    /* pre-scan the imput string to check for decimals */
    while ( *pos == '.' || *pos == '_' || isDIGIT(*pos) )
    {
	if ( *pos == '.' )
	{
	    if ( saw_under )
		Perl_croak(aTHX_ "Invalid version format (underscores before decimal)");
	    saw_period++ ;
	}
	else if ( *pos == '_' )
	{
	    if ( saw_under )
		Perl_croak(aTHX_ "Invalid version format (multiple underscores)");
	    saw_under = 1;
	}
	pos++;
    }
    pos = s;

    if (*pos == 'v') {
	pos++;  /* get past 'v' */
	qv = 1; /* force quoted version processing */
    }
    while (isDIGIT(*pos))
	pos++;
    if (!isALPHA(*pos)) {
	I32 rev;

	if (*s == 'v') s++;  /* get past 'v' */

	for (;;) {
	    rev = 0;
	    {
  		/* this is atoi() that delimits on underscores */
  		char *end = pos;
  		I32 mult = 1;
 		I32 orev;
  		if ( s < pos && s > start && *(s-1) == '_' ) {
 			mult *= -1;	/* alpha version */
  		}
		/* the following if() will only be true after the decimal
		 * point of a version originally created with a bare
		 * floating point number, i.e. not quoted in any way
		 */
 		if ( !qv && s > start+1 && saw_period == 1 ) {
		    mult *= 100;
 		    while ( s < end ) {
 			orev = rev;
 			rev += (*s - '0') * mult;
 			mult /= 10;
 			if ( PERL_ABS(orev) > PERL_ABS(rev) )
 			    Perl_croak(aTHX_ "Integer overflow in version");
 			s++;
 		    }
  		}
 		else {
 		    while (--end >= s) {
 			orev = rev;
 			rev += (*end - '0') * mult;
 			mult *= 10;
 			if ( PERL_ABS(orev) > PERL_ABS(rev) )
 			    Perl_croak(aTHX_ "Integer overflow in version");
 		    }
 		} 
  	    }
  
  	    /* Append revision */
	    av_push((AV *)sv, newSViv(rev));
	    if ( (*pos == '.' || *pos == '_') && isDIGIT(pos[1]))
		s = ++pos;
	    else if ( isDIGIT(*pos) )
		s = pos;
	    else {
		s = pos;
		break;
	    }
	    while ( isDIGIT(*pos) ) {
		if ( saw_period == 1 && pos-s == 3 )
		    break;
		pos++;
	    }
	}
    }
    if ( qv ) { /* quoted versions always become full version objects */
	I32 len = av_len((AV *)sv);
	for ( len = 2 - len; len != 0; len-- )
	    av_push((AV *)sv, newSViv(0));
    }
    return s;
}

/*
=for apidoc new_version

Returns a new version object based on the passed in SV:

    SV *sv = new_version(SV *ver);

Does not alter the passed in ver SV.  See "upg_version" if you
want to upgrade the SV.

=cut
*/

SV *
Perl_new_version(pTHX_ SV *ver)
{
    SV *rv = newSV(0);
    if ( sv_derived_from(ver,"version") ) /* can just copy directly */
    {
	I32 key;
	AV *av = (AV *)SvRV(ver);
	SV* sv = newSVrv(rv, "version"); /* create an SV and upgrade the RV */
	(void)sv_upgrade(sv, SVt_PVAV); /* needs to be an AV type */
	for ( key = 0; key <= av_len(av); key++ )
	{
	    I32 rev = SvIV(*av_fetch(av, key, FALSE));
	    av_push((AV *)sv, newSViv(rev));
	}
	return rv;
    }
#ifdef SvVOK
    if ( SvVOK(ver) ) { /* already a v-string */
	char *version;
	MAGIC* mg = mg_find(ver,PERL_MAGIC_vstring);
	version = savepvn( (const char*)mg->mg_ptr,mg->mg_len );
	sv_setpv(rv,version);
	Safefree(version);
    }
    else {
#endif
    sv_setsv(rv,ver); /* make a duplicate */
#ifdef SvVOK
    }
#endif
    upg_version(rv);
    return rv;
}

/*
=for apidoc upg_version

In-place upgrade of the supplied SV to a version object.

    SV *sv = upg_version(SV *sv);

Returns a pointer to the upgraded SV.

=cut
*/

SV *
Perl_upg_version(pTHX_ SV *ver)
{
    char *version;
    bool qv = 0;

    if ( SvNOK(ver) ) /* may get too much accuracy */ 
    {
	char tbuf[64];
	sprintf(tbuf,"%.9"NVgf, SvNVX(ver));
	version = savepv(tbuf);
    }
#ifdef SvVOK
    else if ( SvVOK(ver) ) { /* already a v-string */
	MAGIC* mg = mg_find(ver,PERL_MAGIC_vstring);
	version = savepvn( (const char*)mg->mg_ptr,mg->mg_len );
	qv = 1;
    }
#endif
    else /* must be a string or something like a string */
    {
	STRLEN n_a;
	version = savepv(SvPV(ver,n_a));
    }
    (void)scan_version(version, ver, qv);
    Safefree(version);
    return ver;
}


/*
=for apidoc vnumify

Accepts a version object and returns the normalized floating
point representation.  Call like:

    sv = vnumify(rv);

NOTE: you can pass either the object directly or the SV
contained within the RV.

=cut
*/

SV *
Perl_vnumify(pTHX_ SV *vs)
{
    I32 i, len, digit;
    SV *sv = newSV(0);
    if ( SvROK(vs) )
	vs = SvRV(vs);
    len = av_len((AV *)vs);
    if ( len == -1 )
    {
	Perl_sv_catpv(aTHX_ sv,"0");
	return sv;
    }
    digit = SvIVX(*av_fetch((AV *)vs, 0, 0));
    Perl_sv_setpvf(aTHX_ sv,"%d.", (int)PERL_ABS(digit));
    for ( i = 1 ; i < len ; i++ )
    {
	digit = SvIVX(*av_fetch((AV *)vs, i, 0));
	Perl_sv_catpvf(aTHX_ sv,"%03d", (int)PERL_ABS(digit));
    }
    if ( len > 0 )
    {
	digit = SvIVX(*av_fetch((AV *)vs, len, 0));
	if ( (int)PERL_ABS(digit) != 0 || len == 1 )
	{
	    /* Don't display additional trailing zeros */
	    Perl_sv_catpvf(aTHX_ sv,"%03d", (int)PERL_ABS(digit));
	}
    }
    else /* len == 0 */
    {
	 Perl_sv_catpv(aTHX_ sv,"000");
    }
    return sv;
}

/*
=for apidoc vnormal

Accepts a version object and returns the normalized string
representation.  Call like:

    sv = vnormal(rv);

NOTE: you can pass either the object directly or the SV
contained within the RV.

=cut
*/

SV *
Perl_vnormal(pTHX_ SV *vs)
{
    I32 i, len, digit;
    SV *sv = newSV(0);
    if ( SvROK(vs) )
	vs = SvRV(vs);
    len = av_len((AV *)vs);
    if ( len == -1 )
    {
	Perl_sv_catpv(aTHX_ sv,"");
	return sv;
    }
    digit = SvIVX(*av_fetch((AV *)vs, 0, 0));
    Perl_sv_setpvf(aTHX_ sv,"%"IVdf,(IV)digit);
    for ( i = 1 ; i <= len ; i++ )
    {
	digit = SvIVX(*av_fetch((AV *)vs, i, 0));
	if ( digit < 0 )
	    Perl_sv_catpvf(aTHX_ sv,"_%"IVdf,(IV)-digit);
	else
	    Perl_sv_catpvf(aTHX_ sv,".%"IVdf,(IV)digit);
    }
    
    if ( len <= 2 ) { /* short version, must be at least three */
	for ( len = 2 - len; len != 0; len-- )
	    Perl_sv_catpv(aTHX_ sv,".0");
    }

    return sv;
} 

/*
=for apidoc vstringify

In order to maintain maximum compatibility with earlier versions
of Perl, this function will return either the floating point
notation or the multiple dotted notation, depending on whether
the original version contained 1 or more dots, respectively

=cut
*/

SV *
Perl_vstringify(pTHX_ SV *vs)
{
    I32 i, len, digit;
    if ( SvROK(vs) )
	vs = SvRV(vs);
    len = av_len((AV *)vs);
    
    if ( len < 2 )
	return vnumify(vs);
    else
	return vnormal(vs);
}

/*
=for apidoc vcmp

Version object aware cmp.  Both operands must already have been 
converted into version objects.

=cut
*/

int
Perl_vcmp(pTHX_ SV *lsv, SV *rsv)
{
    I32 i,l,m,r,retval;
    if ( SvROK(lsv) )
	lsv = SvRV(lsv);
    if ( SvROK(rsv) )
	rsv = SvRV(rsv);
    l = av_len((AV *)lsv);
    r = av_len((AV *)rsv);
    m = l < r ? l : r;
    retval = 0;
    i = 0;
    while ( i <= m && retval == 0 )
    {
	I32 left  = SvIV(*av_fetch((AV *)lsv,i,0));
	I32 right = SvIV(*av_fetch((AV *)rsv,i,0));
	bool lalpha = left  < 0 ? 1 : 0;
	bool ralpha = right < 0 ? 1 : 0;
	left  = abs(left);
	right = abs(right);
	if ( left < right || (left == right && lalpha && !ralpha) )
	    retval = -1;
	if ( left > right || (left == right && ralpha && !lalpha) )
	    retval = +1;
	i++;
    }

    if ( l != r && retval == 0 ) /* possible match except for trailing 0's */
    {
	if ( l < r )
	{
	    while ( i <= r && retval == 0 )
	    {
		if ( SvIV(*av_fetch((AV *)rsv,i,0)) != 0 )
		    retval = -1; /* not a match after all */
		i++;
	    }
	}
	else
	{
	    while ( i <= l && retval == 0 )
	    {
		if ( SvIV(*av_fetch((AV *)lsv,i,0)) != 0 )
		    retval = +1; /* not a match after all */
		i++;
	    }
	}
    }
    return retval;
}
