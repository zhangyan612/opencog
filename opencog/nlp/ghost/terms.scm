;; GHOST DSL for authoring rules
;;
;; Assorted functions for translating individual terms into Atomese fragments.

(define (create-concept NAME MEMBERS)
  "Create named concepts with explicit membership lists.
   The first argument is the name of the concept, and the rest is the
   list of words and/or concepts that will be considered as the members
   of the concept."
  ; Convert the member in the form of a string into an atom, which can
  ; either be a WordNode, LemmaNode, ConceptNode, or a PhraseNode.
  (define (member-words STR)
    (let ((words (string-split STR #\sp)))
      (if (= 1 (length words))
          (let ((w (car words)))
               (cond ((string-prefix? "~" w) (Concept (substring w 1)))
                     ((is-lemma? w) (LemmaNode w))
                     (else (WordNode w))))
          (PhraseNode STR))))
  (append-map (lambda (m) (list (Reference (member-words m) (Concept NAME))))
              MEMBERS))

(define (create-shared-goal GOAL)
  "Create a topic level goal that will be shared among the rules under the
   same topic."
  (set! shared-goals GOAL))

(define (word STR)
  "Literal word occurrence."
  (let* ((v1 (WordNode STR))
         (v2 (Variable (gen-var STR #f)))
         (l (WordNode (get-lemma STR)))
         (v (list (TypedVariable v2 (Type "WordInstanceNode"))))
         (c (list (WordInstanceLink v2 (Variable "$P"))
                  (ReferenceLink v2 v1))))
    (list v c (list v1) (list l))))

(define (lemma STR)
  "Lemma occurrence, aka canonical form of a term.
   This is the default for word mentions in the rule pattern."
  (let* ((v1 (Variable (gen-var STR #t)))
         (v2 (Variable (gen-var STR #f)))
         (l (WordNode (get-lemma STR)))
         (v (list (TypedVariable v1 (Type "WordNode"))
                  (TypedVariable v2 (Type "WordInstanceNode"))))
         ; Note: This converts STR to its lemma
         (c (list (ReferenceLink v2 v1)
                  (LemmaLink v2 l)
                  (WordInstanceLink v2 (Variable "$P")))))
    (list v c (list v1) (list l))))

(define (phrase STR)
  "Occurrence of a phrase or a group of words.
   All the words are assumed to be literal / non-canonical."
  (fold (lambda (wd lst)
                (list (append (car lst) (car wd))
                      (append (cadr lst) (cadr wd))
                      (append (caddr lst) (caddr wd))
                      (append (cadddr lst) (cadddr wd))))
        (list '() '() '() '())
        (map word (string-split STR #\sp))))

(define-public (ghost-concept? CONCEPT . GRD)
  "Check if the value grounded for the GlobNode is actually a member
   of the concept."
  (cog-logger-debug ghost-logger
    "In ghost-concept? CONCEPT: ~aGRD: ~a" CONCEPT GRD)
  (if (is-member? GRD (get-members CONCEPT))
      (stv 1 1)
      (stv 0 1)))

(define (concept STR)
  "Occurrence of a concept."
  (let ((g1 (Glob (gen-var STR #t)))
        (g2 (Glob (gen-var STR #f)))
        (clength (concept-length (Concept STR))))
    (list (list (TypedVariable g1 (TypeSet (Type "WordNode")
                                           (Interval (Number 1)
                                                     (Number clength))))
                (TypedVariable g2 (TypeSet (Type "WordNode")
                                           (Interval (Number 1)
                                                     (Number clength)))))
          (list (Evaluation (GroundedPredicate "scm: ghost-concept?")
                            (List (Concept STR) g1)))
          (list g1)
          (list g2))))

(define-public (ghost-choices? CHOICES . GRD)
  "Check if the value grounded for the GlobNode is actually a member
   of the list of choices."
  (cog-logger-debug ghost-logger
    "In ghost-choices? CHOICES: ~aGRD: ~a" CHOICES GRD)
  (let* ((chs (cog-outgoing-set CHOICES))
         (cpts (append-map get-members (cog-filter 'ConceptNode chs))))
        (if (is-member? GRD (append chs cpts))
            (stv 1 1)
            (stv 0 1))))

(define (choices TERMS)
  "Occurrence of a list of choices. Existence of either one of
   the words/lemmas/phrases/concepts in the list will be considered
   as a match."
  (let ((g1 (Glob (gen-var "choices" #t)))
        (g2 (Glob (gen-var "choices" #f)))
        (tlength (term-length TERMS)))
    (list (list (TypedVariable g1 (TypeSet (Type "WordNode")
                                           (Interval (Number 1)
                                                     (Number tlength))))
                (TypedVariable g2 (TypeSet (Type "WordNode")
                                           (Interval (Number 1)
                                                     (Number tlength)))))
          (list (Evaluation (GroundedPredicate "scm: ghost-choices?")
                            (List (List (terms-to-atomese TERMS)) g1)))
          (list g1)
          (list g2))))

(define-public (ghost-negation? . TERMS)
  "Check if the input sentence has none of the terms specified."
  (let* ; Get the raw text input
        ((sent (car (cog-chase-link 'StateLink 'SentenceNode ghost-anchor)))
         (rtxt (cog-name (car (cog-chase-link 'ListLink 'Node sent))))
         (ltxt (string-join (map get-lemma (string-split rtxt #\sp)))))
        (if (any (lambda (t) (text-contains? rtxt ltxt t)) TERMS)
            (stv 0 1)
            (stv 1 1))))

(define (negation TERMS)
  "Absent of a term or a list of terms (words/phrases/concepts)."
  (list '()  ; No variable declaration
        (list (Evaluation (GroundedPredicate "scm: ghost-negation?")
                          (List (terms-to-atomese TERMS))))
        ; Nothing for the word-seq and lemma-seq
        '() '()))

(define (wildcard LOWER UPPER)
  "Occurrence of a wildcard that the number of atoms to be matched
   can be restricted.
   Note: -1 in the upper bound means infinity."
  (let* ((g1 (Glob (gen-var "wildcard" #t)))
         (g2 (Glob (gen-var "wildcard" #f))))
    (list (list (TypedVariable g1
                (TypeSet (Type "WordNode")
                         (Interval (Number LOWER) (Number UPPER))))
                (TypedVariable g2
                (TypeSet (Type "WordNode")
                         (Interval (Number LOWER) (Number UPPER)))))
        '()
        (list g1)
        (list g2))))

; TODO: Should be placed in the action of the rule
(define-public (ghost-record-groundings WGRD LGRD)
  "Record the groundings of a variable, in both original words and lemmas.
   They will be referenced at the stage of evaluating the context of the
   psi-rules, or executing the action of the psi-rules."
  (cog-logger-debug ghost-logger "--- Recording groundings:\n~a\n~a" WGRD LGRD)
  (set! var-grd-words (assoc-set! var-grd-words (gar WGRD) (gdr WGRD)))
  (set! var-grd-lemmas (assoc-set! var-grd-lemmas (gar LGRD) (gdr LGRD)))
  (stv 1 1))

(define-public (ghost-get-lemma . WORD)
  "Get the lemma of WORD, where WORD can be one or more WordNodes."
  (List (map Word (map get-lemma (map cog-name WORD)))))

(define (variable VAR . GRD)
  "Occurence of a variable. The value grounded for it needs to be recorded.
   VAR is a number, it will be included as part of the variable name.
   GRD can either be a VariableNode or a GlobNode, which pass the actual
   value grounded in original words at runtime."
  (Evaluation (GroundedPredicate "scm: ghost-record-groundings")
    (List (List (ghost-var-word VAR) (List GRD))
          (List (ghost-var-lemma VAR)
                (ExecutionOutput (GroundedSchema "scm: ghost-get-lemma")
                                 (List GRD))))))

(define (context-function NAME ARGS)
  "Occurrence of a function in the context of a rule.
   The DefinedPredicateNode named NAME should have already been defined."
  (if (equal? 1 (length ARGS))
      (Put (DefinedPredicate NAME) ARGS)
      (Put (DefinedPredicate NAME) (List ARGS))))

(define (action-function NAME ARGS)
  "Occurrence of a function in the action of a rule.
   The DefinedSchemaNode named NAME should have already been defined."
  (if (equal? 1 (length ARGS))
      (Put (DefinedSchema NAME) ARGS)
      (Put (DefinedSchema NAME) (List ARGS))))

(define-public (ghost-pick-action ACTIONS)
  "The actual Scheme function being called by the GroundedSchemaNode
   for picking one of the ACTIONS randomly."
  (define os (cog-outgoing-set ACTIONS))
  (list-ref os (random (length os) (random-state-from-platform))))

(define (action-choices ACTIONS)
  "Pick one of the ACTIONS randomly."
  (ExecutionOutput (GroundedSchema "scm: ghost-pick-action")
                   (Set ACTIONS)))

(define-public (ghost-get-var-words VAR)
  "Get the grounding of VAR, in original words."
  (define grd (assoc-ref var-grd-words VAR))
  (if (equal? grd #f)
      (List)
      grd))

(define (get-var-words NUM)
  "Get the value grounded for a variable, in original words."
  (ExecutionOutput (GroundedSchema "scm: ghost-get-var-words")
                   (List (ghost-var-word NUM))))

(define-public (ghost-get-var-lemmas VAR)
  "Get the grounding of VAR, in lemmas."
  (define grd (assoc-ref var-grd-lemmas VAR))
  (if (equal? grd #f) (List) grd))

(define (get-var-lemmas NUM)
  "Get the value grounded for a variable, in lemmas."
  (ExecutionOutput (GroundedSchema "scm: ghost-get-var-lemmas")
                   (List (ghost-var-lemma NUM))))

(define-public (ghost-get-user-variable UVAR)
  "Get the value stored for VAR."
  (define grd (assoc-ref uvars UVAR))
  (if (equal? grd #f) (List) grd))

(define (get-user-variable UVAR)
  "Get the value of a user variable."
  (ExecutionOutput (GroundedSchema "scm: ghost-get-user-variable")
                   (List (ghost-uvar UVAR))))

(define-public (ghost-set-user-variable UVAR VAL)
  "Assign VAL to UVAR."
  (set! uvars (assoc-set! uvars UVAR VAL))
  (True))

(define (set-user-variable UVAR VAL)
  "Assign a string value to a user variable."
  (ExecutionOutput (GroundedSchema "scm: ghost-set-user-variable")
                   (List (ghost-uvar UVAR) VAL)))

(define-public (ghost-user-variable-exist? UVAR)
  "Check if UVAR has been defined."
  (if (equal? (assoc-ref uvars UVAR) #f)
      (stv 0 1)
      (stv 1 1)))

(define (uvar-exist? UVAR)
  "Check if a user variable has been defined."
  (Evaluation (GroundedPredicate "scm: ghost-user-variable-exist?")
              (List (ghost-uvar UVAR))))

(define-public (ghost-user-variable-equal? UVAR VAL)
  "Check if the value of UVAR equals VAL."
  (if (equal? (assoc-ref uvars UVAR) VAL)
      (stv 1 1)
      (stv 0 1)))

(define (uvar-equal? UVAR VAL)
  "Check if the value of the user variable VAR equals to VAL."
  ; TODO: VAL can also be a concept etc?
  (Evaluation (GroundedPredicate "scm: ghost-user-variable-equal?")
              (List (ghost-uvar UVAR) (Word VAL))))

(define-public (ghost-execute-action . ACTIONS)
  "Say the text and update the internal state."
  (define (extract-txt actions)
    ; TODO: Right now it is extracting text only, but should be extended
    ; to support actions that contains are not text as well.
    (string-join (append-map
      (lambda (a)
        (cond ((cog-link? a)
               (list (extract-txt (cog-outgoing-set a))))
              ((equal? 'WordNode (cog-type a))
               (list (cog-name a)))
              ; TODO: things other than text
              (else '())))
        actions)))
  (define txt (extract-txt ACTIONS))
  ; Is there anything to say?
  (if (not (string-null? (string-trim txt)))
      (begin (cog-logger-info ghost-logger "Say: \"~a\"" txt)
             (cog-execute! (Put (DefinedPredicate "Say") (Node txt)))))
  ; Reset the state
  (State ghost-anchor (Concept "Default State")))
