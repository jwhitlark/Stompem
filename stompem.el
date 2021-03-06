;;; stompem.el -- Connect and send messages via STOMP (Streaming Text Orientated Messaging Protocol)
;;; Copyright (c) 2010 Jason A. Whitlark.  All rights reserved.

;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are
;;; met:

;;;   * Redistributions of source code must retain the above copyright
;;;     notice, this list of conditions and the following disclaimer.

;;;   * Redistributions in binary form must reproduce the above copyright
;;;     notice, this list of conditions and the following disclaimer in the
;;;     documentation and/or other materials provided with the distribution.

;;;   * Neither the name of the author nor the names of its
;;;     contributors may be used to endorse or promote products derived from
;;;     this software without specific prior written permission.

;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
;;; IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
;;; TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
;;; PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR
;;; CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
;;; EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
;;; PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;;; PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;;; LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


;;; This is version 0.8 of 22 Jun 2010


; TODO: Transaction support
; TODO: Prompt to connect on send-* if no connection exists.
; TODO: Automatically add content-length header to messages.
; TODO: Add config option for common queues, then merge with dest-hist
; TODO: Add filters on output to allow subscriptions to different
;       queues to put messages in different buffers.  see 37.9.2 "Process Filter Functions" in elisp manual.

; Recommended autoload statements (add the following to your .emacs file.)
; (autoload 'stompem-connect "stompem" "Connect to a Stomp server in order to send/receive messages." t)

; You can override stompem-host, stompem-port, stompem-user, and stompem-pass in your .emacs file
; Additionally, you can define stompem-destination-history to provide a starting list of queues.


(defconst stompem--client-process-name "stompem-client")
(defsubst stompem--client-process () (get-process stompem--client-process-name))

(defvar stompem-host "localhost" "Host to connect to.")
(defvar stompem-port 61613 "Port to connect to.")
(defvar stompem-user "" "Username to connect with.")
(defvar stompem-pass "" "Passcode to connect with.")

(defvar stompem-destination-history '())

(defun stompem-process-exists-p ()
  "Is there an existing stompem process?"
  (eq 'open (process-status (stompem--client-process))))

(defun stompem-chomp (str)
  "Simple chomp implementation."
  (if (and (stringp str) (string-match "\r?\n$" str))
      (replace-match "" t nil str)
    str))

(defun stompem-client-notify-connect (&rest args)
  "Low level function"
  (message (format "Connection message [%s]" (mapcar #'stompem-chomp args))))

(defun stompem-client-open (host port)
  "Low level function"
  (make-network-process :name stompem--client-process-name
                        :host host
                        :service port
                        :nowait t
			:buffer (get-buffer-create "stompem-messages")
                        :sentinel #'stompem-client-notify-connect)
  (sit-for 1))

(defun stompem-client-close ()
  "Low level function"
  (delete-process (stompem--client-process)))

(defun stompem-client-send-string (str)
  "Low level function"
  (process-send-string (stompem--client-process) (concat str "\r\n")))

(defun stompem-make-header (key val)
  "Low level function"
  (format "%s:%s" key val))

(defun stompem-make-header-from-pair (pair)
  "Low level function"
  (stompem-make-header (car pair) (cadr pair)))

(defun stompem-make-headers (list-of-pairs)
  "Low level function"
  (mapconcat 'identity (mapcar 'stompem-make-header-from-pair list-of-pairs) "\r\n"))

(defun stompem-split-header (line)
  "Low level function"
  (split-string line ":"))

(defun stompem-split-headers (lines)
  "Low level function"
  (mapcar 'stompem-split-header (split-string lines "\n")))

(defun stompem-send-command (cmd headers body)
  "Lowest level interface to send a stomp command."
  (interactive "sCommand: \nsheaders: \nsBody:")
  ;; Following doesn't work yet.  It's supposed to interactively set
  ;; up a connection if one doesn't exist.
  ;; (when (called-interactively-p)
  ;; (if (not (stompem-process-exists-p)) (command-execute
  ;; 'stompem-connect)))
  (let* ((command (upcase cmd))
	(headers-f (stompem-make-headers headers))
	(msg (concat command "\r\n"
		     headers-f "\r\n\r\n"
		     body " ")))
    ;(display-message-or-buffer msg) ; TODO: Remove after testing is compete.
    (stompem-client-send-string msg)))

(defun stompem-send-message (destination body)
  "Send a message to the given destination."
  (interactive (list (read-string "Destination: " (car stompem-destination-history) '(stompem-destination-history . 1))
		     (read-string "Body: ")))
  (progn
    (push destination stompem-destination-history)
    (stompem-send-command "SEND" `(("destination" ,destination)) body)))


(defun stompem-send-region (destination start end)
  "Send the current region to the given destination as a message body."
  (interactive
   (let ((string (read-string "Destination: " (car stompem-destination-history) '(stompem-destination-history . 1))))
     (list string (region-beginning) (region-end))))
  (stompem-send-message destination (buffer-substring start end)))

(defun stompem-send-buffer (destination buffer)
  "Send the given buffer to the given destination as a message body."
  (interactive (list (read-string "Destination: " (car stompem-destination-history) '(stompem-destination-history . 1))
		     (read-buffer "Buffer: ")))
  (stompem-send-message destination (save-current-buffer (set-buffer buffer)
							 (buffer-substring (point-min) (point-max)))))

(defun stompem-subscribe (destination)
  "Subscribe to a stomp queue.  Messages appear in stomp-messages buffer."
  (interactive (list (read-string "Destination: " (car stompem-destination-history) '(stompem-destination-history . 1))))
  (progn
    (push destination stompem-destination-history)
    (stompem-send-command "SUBSCRIBE" `(("destination" ,destination)) "")))

(defun stompem-unsubscribe (destination)
  "Unsubscribe from a stomp queue."
  (interactive (list (read-string "Destination: " (car stompem-destination-history) '(stompem-destination-history . 1))))
  (progn
    (push destination stompem-destination-history)
    (stompem-send-command "UNSUBSCRIBE" `(("destination" ,destination)) "")))

(defun stompem-connect (host port user pass)
  "Connect to a stomp server."
  (interactive (list (read-string "Host: " stompem-host)
		     (string-to-number (read-string "Port: " (number-to-string stompem-port)))
		     (read-string "Username: " stompem-user)
		     (read-string "Passcode: " stompem-pass)))
  (progn
    (stompem-client-open host port)
    (stompem-send-command "CONNECT" `(("login" ,user) (passcode ,pass)) "")))

(defun stompem-disconnect ()
  "Disconnect from a stomp server."
  (interactive)
  (stompem-client-close))


(provide 'stompem)

;;; stompem.el ends here
