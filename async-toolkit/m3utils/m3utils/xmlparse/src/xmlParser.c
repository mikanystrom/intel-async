/* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. */
/* SPDX-License-Identifier: Apache-2.0 */

/*****************************************************************
 * outline.c
 *
 * Copyright 1999, Clark Cooper
 * All rights reserved.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the license contained in the
 * COPYING file that comes with the expat distribution.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * Read an XML document from standard input and print an element
 * outline on standard output.
 * Must be used with Expat compiled for UTF-8 output.
 * extensively modified and extended by 
 *    Mika Nystrom <mika@alum.mit.edu><mika.nystroem@intel.com>
 */


#include <string.h>
#include <stdio.h>

/* linux sticks just about EVERYTHING in /usr (not /usr/local like BSD) */
#include <expat.h>

#define DEBUG 0

#ifdef XML_LARGE_SIZE
#if defined(XML_USE_MSC_EXTENSIONS) && _MSC_VER < 1400
#define XML_FMT_INT_MOD "I64"
#else
#define XML_FMT_INT_MOD "ll"
#endif
#else
#define XML_FMT_INT_MOD "l"
#endif

#define BUFFSIZE        8192

char Buff[BUFFSIZE];

int Depth;

typedef void (startCall)(void *context, void *stuff, const char *el);
typedef void (endCall)(void *context, void *stuff);
typedef void (attrCall)(void *context, void *stuff, const char *tag, const char *attr);
typedef void (charDataCall)(void *context, void *stuff, int len, const char *data);

typedef struct {
  void *stuff;
  startCall *s;
  attrCall *a;
  endCall *e;
  charDataCall *c;
  void *context;
} UD;

static void XMLCALL
start(void *data, const char *el, const char **attr)
{
  int i;
  UD *m3callbacks = data;

#if DEBUG
  for (i = 0; i < Depth; i++)
    printf("  ");

  printf("%s", el);
#endif
  
  if (m3callbacks->s) m3callbacks->s(m3callbacks->context, m3callbacks->stuff,el);

  for (i = 0; attr[i]; i += 2) {
#if DEBUG
    printf(" %s='%s'", attr[i], attr[i + 1]);
#endif
    if (m3callbacks->a) m3callbacks->a(m3callbacks->context, m3callbacks->stuff,
				       attr[i], attr[i + 1]);
  }

#if DEBUG
  printf("\n");
#endif
  Depth++;
}

static void XMLCALL
end(void *data, const char *el)
{
  UD *m3callbacks = data;

  if (m3callbacks->e) m3callbacks->e(m3callbacks->context, m3callbacks->stuff);

  Depth--;
}

static void XMLCALL
characterdata(void *data, const char *s, int len)
{
  UD *m3callbacks = data;

  if (m3callbacks->c) m3callbacks->c(m3callbacks->context, m3callbacks->stuff, len, s);
}

int
xmlParserString(const char *string,
	      void *stuff, startCall s, attrCall a, endCall e, charDataCall c)
{
  UD *m3callbacks=malloc(sizeof(UD));

  XML_Parser p = XML_ParserCreate(NULL);
  if (! p) {
    fprintf(stderr, "Couldn't allocate memory for parser\n");
    return -1;
  }

  m3callbacks->stuff = stuff;
  m3callbacks->s = s;
  m3callbacks->a = a;
  m3callbacks->e = e;
  m3callbacks->c = c;
  m3callbacks->context = NULL;
  
  XML_SetUserData(p,m3callbacks);

  XML_SetElementHandler(p, start, end);
  XML_SetCharacterDataHandler(p, characterdata);

	if (XML_Parse(p, string, strlen(string), 1) == XML_STATUS_ERROR) {
		fprintf(stderr, "Parse error at line %" XML_FMT_INT_MOD "u:\n%s\n",
						XML_GetCurrentLineNumber(p),
						XML_ErrorString(XML_GetErrorCode(p)));
		return -1;
	}

	XML_ParserFree(p);
	free(m3callbacks);
      
  return 0;
}

long int
xmlParserMain(const char  *path,
	      void        *stuff,
              startCall    s,
              attrCall     a,
              endCall      e,
              charDataCall c)
{
  FILE *ifp;

  UD *m3callbacks=malloc(sizeof(UD));

  XML_Parser p = XML_ParserCreate(NULL);
  if (! p) {
    fprintf(stderr, "Couldn't allocate memory for parser\n");
    return -1;
  }

  if (path) {
    if ( !(ifp = fopen(path,"r")) ) {
      fprintf(stderr, "xmlParser: FILE %s NOT FOUND.\n", path);
      return -1;
    }
  } else
    ifp = stdin;

  m3callbacks->stuff = stuff;
  m3callbacks->s = s;
  m3callbacks->a = a;
  m3callbacks->e = e;
  m3callbacks->c = c;
  m3callbacks->context = NULL;
    
  XML_SetUserData(p,m3callbacks);

  XML_SetElementHandler(p, start, end);
  XML_SetCharacterDataHandler(p, characterdata);

  { 
    int done;

    do {
      int len;
      
      len = fread(Buff, 1, BUFFSIZE, ifp);
      if (ferror(ifp)) {
	fprintf(stderr, "Read error\n");
	return -1;
      }
      done = feof(ifp);
      
      if (XML_Parse(p, Buff, len, done) == XML_STATUS_ERROR) {
	fprintf(stderr, "Parse error at line %" XML_FMT_INT_MOD "u:\n%s\n",
		XML_GetCurrentLineNumber(p),
		XML_ErrorString(XML_GetErrorCode(p)));
	return -1;
      }
      
    } while (!done);
  }

  if (path) fclose(ifp);

  XML_ParserFree(p);
  free(m3callbacks);

  return 0;
}

struct parse_context {
  UD          *m3callbacks;
  XML_Parser   p;
  const char  *path;
  FILE        *ifp;
};

/**********************************************************************/
/* functions below are for use with "detached" parsing */

void *
xmlParserInit(const char  *patha,
	      void        *stuff,
              startCall    s,
              attrCall     a,
              endCall      e,
              charDataCall c)
{
  struct parse_context *context=malloc(sizeof(struct parse_context));

  context->path = patha;
  context->m3callbacks=malloc(sizeof(UD));

  context->p = XML_ParserCreate(NULL);
  if (!context->p) {
    fprintf(stderr, "Couldn't allocate memory for parser\n");
    return NULL;
  }

  if (context->path) {
    if ( !(context->ifp = fopen(context->path,"r")) ) {
      fprintf(stderr, "xmlParser: FILE %s NOT FOUND.\n", context->path);
      return NULL;
    }
  } else
    context->ifp = stdin;

  context->m3callbacks->stuff = stuff;
  context->m3callbacks->s = s;
  context->m3callbacks->a = a;
  context->m3callbacks->e = e;
  context->m3callbacks->c = c;
  context->m3callbacks->context = context;

  XML_SetUserData(context->p,context->m3callbacks);

  XML_SetElementHandler(context->p, start, end);
  XML_SetCharacterDataHandler(context->p, characterdata);

  return (void *)context;
}

long int
xmlParseContextIsNull(void *context)
{
  return context == NULL;
}

long int
xmlParseChunk(void *ca)
{
  struct parse_context *context = (struct parse_context *)ca;
  int len;
  int done;
      
  len = fread(Buff, 1, BUFFSIZE, context->ifp);
  if (ferror(context->ifp)) {
    fprintf(stderr, "Read error\n");
    return -1;
  }
  done = feof(context->ifp);
  
  if (XML_Parse(context->p, Buff, len, done) == XML_STATUS_ERROR) {
    fprintf(stderr, "Parse error at line %" XML_FMT_INT_MOD "u:\n%s\n",
            XML_GetCurrentLineNumber(context->p),
            XML_ErrorString(XML_GetErrorCode(context->p)));
    return -1;
  }

  return !done;
}

void
xmlParseDestroy(void *ca)
{
  struct parse_context *context = (struct parse_context *)ca;
  if (context->path) fclose(context->ifp);

  XML_ParserFree(context->p);
  free(context->m3callbacks);
}

long int
xmlParseStopParser(void *ca, int resumable)
{
  struct parse_context *context = (struct parse_context *)ca;
  return XML_StopParser(context->p, resumable);
}

long int
xmlParseResumeParser(void *ca)
{
  struct parse_context *context = (struct parse_context *)ca;
  return XML_ResumeParser(context->p);
}

/**********************************************************************/
/* export constants -- to Modula-3 */

long int
xmlStatusError(void)
{
  return XML_STATUS_ERROR;
}

long int
xmlStatusOK(void)
{
  return XML_STATUS_OK;
}

long int
xmlStatusSuspended(void)
{
  return XML_STATUS_SUSPENDED;
}

/**********************************************************************/

long int
xmlParserIsSuspended(void *ca)
{
  struct parse_context *context = (struct parse_context *)ca;
  XML_ParsingStatus status;

  XML_GetParsingStatus(context->p, &status);
  return status.parsing == XML_SUSPENDED;
}

/**********************************************************************/

/* below here:
   a simple memory allocation scheme to copy a small batch of data 

   We need this because even when we stop the XML_Parse parser, we are
   not guaranteed that we can use its references after the callback
   returns, even though the parser is stopped!  So we make a copy of
   the references, and we free that copy when we are done handling
   them (not long after).

   If expat just guaranteed that the references were OK to use until
   the parser is restarted we wouldnt need any of this stuff.  But I
   dont think it does.  The documentation doesnt seem to say but I
   believe we had problems when we tried.

*/

static char     *copyBuff = NULL;
static long int  copyBuff_size;
static long int  copyBuff_p;

static void
copyBuff_check_create(void)
{
  const long int minsz = 16;
  
  if (copyBuff == NULL) {
    copyBuff      = (char *)malloc(minsz);
    copyBuff_size =  minsz;
    copyBuff_p    = 0;
  }
}

const char *
xmlLenCopy(const char *s, long int len)
/* copy an array of characters */
{
  char *tgt;
  copyBuff_check_create();

  if (copyBuff_p + len >= copyBuff_size) {
    copyBuff_size = copyBuff_p + len;
    copyBuff = realloc(copyBuff, copyBuff_size);
  }

  tgt = copyBuff + copyBuff_p;
  memcpy(tgt, s, len);
  copyBuff_p += len;

  return tgt;
}

const char *
xmlNullCopy(const char *s)
/* copy a null-terminated string */
{
  int len = strlen(s) + 1; /* mem req't includes term null */
  const char *res = xmlLenCopy(s, len);
#if 0
  printf("xmlNullCopy %s -> %s\n", s, res);
#endif
  return res;
}

void
xmlCopyFree(void)
/* free everything copied since the last call to xmlCopyFree */
{
  copyBuff_p = 0;
}
