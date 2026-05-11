---
title: "MoviePy: Video Editing with Python"
type: source
topic: video-processing
tags: ['video-editing', 'python', 'ffmpeg', 'gstreamer']
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
status: research-draft
origin: "https://github.com/Zulko/moviepy"
---
# MoviePy: Video Editing with Python

MoviePy is a Python library for video editing that supports common audio and video formats, offering functionalities like cutting, concatenating, and applying effects to videos.

## Introduction and Capabilities

MoviePy is a Python library for video editing: cuts, concatenations, title insertions, video compositing (a.k.a. non-linear editing), video processing, and creation of custom effects.

MoviePy can read and write all the most common audio and video formats, including GIF, and runs on Windows/Mac/Linux, with Python 3.9+.

Under the hood, MoviePy imports media (video frames, images, sounds) and converts them into Python objects (numpy arrays) so that every pixel becomes accessible, and video or audio effects can be defined in just a few lines of code (see the built-in effects for examples).

The library also provides ways to mix clips together (concatenations, playing clips side by side or on top of each other with transparency, etc.). The final clip is then encoded back into mp4/webm/gif/etc.

This makes MoviePy very flexible and approachable, albeit slower than using [[ffmpeg-entity|ffmpeg]] directly due to heavier data import/export operations.

## Key claims

- MoviePy supports common audio and video formats, including GIF.
- MoviePy runs on Windows/Mac/Linux with Python 3.9+.
- MoviePy can read and write all the most common audio and video formats.

## Open questions

- How does MoviePy handle hardware acceleration compared to other Python video processing libraries like [[pyav-entity|PyAV]]?
- What are the specific breaking changes introduced in MoviePy v2.0, and how do they affect existing codebases?
