/**
  Oxford Laser Post Processor
  Copyright (C) 2015-2016 by MIT CBA
  Will Langford

  Derived from Jet template
  Copyright (C) 2015-2016 by Autodesk, Inc.
  All rights reserved.
  Jet template post processor configuration. This post is intended to show
  the capabilities for use with waterjet, laser, and plasma cutters. It only
  serves as a template for customization for an actual CNC.

  $Date: 2016-05-25 $
*/

description = "Oxford Laser";
vendor = "Oxford";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2015-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 39000;

longDescription = "This post enables 'jet' toolpaths to be exported for use on the Oxford laser.";

capabilities = CAPABILITY_JET;
extension = "pgm";
setCodePage("ascii");

tolerance = spatial(0.0002, MM);

minimumChordLength = spatial(0.001, MM);
minimumCircularRadius = spatial(0.001, MM);
maximumCircularRadius = spatial(100, MM);
minimumCircularSweep = toRad(0.001);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = undefined; // allow any circular motion



// user-defined properties
properties = {
  power: 20,
  feedRate: 5,
  outerLoopPasses: 1, // loops over all of the contours
  innerLoopPasses: 10, // number of passes per contour 
  allowHeadSwitches: true, // output code to allow heads to be manually switched for piercing and cutting
  useRetracts: true, // output retracts - otherwise only output part contours for importing in third-party jet application
};



var gFormat = createFormat({prefix:"G", decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 2)});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-1000

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var feedOutput = createVariable({prefix:"F", force:true}, feedFormat);

// circular output
var iOutput = createReferenceVariable({prefix:"I"}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J"}, xyzFormat);

var gMotionModal = createModal({force:true}, gFormat); // modal group 1 // G0-G3, ...
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;
var split = false;

/**
  Writes the specified block.
*/
function writeBlock() {
    writeWords(arguments);
}

function formatComment(text) {
  return ";" + String(text).replace(/[\(\)]/g, "");
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln(formatComment(text));
}

function onOpen() {

  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  if (hasGlobalParameter("material")) {
    writeComment("MATERIAL = " + getGlobalParameter("material"));
  }

  if (hasGlobalParameter("material-hardness")) {
    writeComment("MATERIAL HARDNESS = " + getGlobalParameter("material-hardness"));
  }

  { // stock - workpiece
    var workpiece = getWorkpiece();
    var delta = Vector.diff(workpiece.upper, workpiece.lower);
    if (delta.isNonZero()) {
    writeComment("THICKNESS = " + xyzFormat.format(workpiece.upper.z - workpiece.lower.z));
    }
  }

  writeln("");
  writeComment("------ Declar and Set Variables ------");
  writeln("DVAR $POWER");
  writeln("DVAR $FEED");
  writeln("DVAR $IL_PASSES");
  writeln("DVAR $OL_PASSES");
  writeln("");
  writeln("$POWER="+properties.power);
  writeln("$FEED="+properties.feedRate);
  writeln("$IL_PASSES="+properties.innerLoopPasses);
  writeln("$OL_PASSES="+properties.outerLoopPasses);
  writeln("");
  
  // ensure both pass variables are >= 1
  if (properties.innerLoopPasses < 1) { properties.innerLoopPasses = 1; }
  if (properties.outerLoopPasses < 1) { properties.outerLoopPasses = 1; }

  // absolute coordinates and feed per min
  writeBlock(gAbsIncModal.format(90));
  
  switch (unit) {
  case IN:
    writeBlock(gUnitModal.format(70));
    break;
  case MM:
    writeBlock(gUnitModal.format(71));
    break;
  }
  writeBlock(gUnitModal.format(92),"X0", "Y0");
  writeBlock(gUnitModal.format(108));
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());

  writeln("");

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  if (insertToolCall) {
    retracted = true;
    onCommand(COMMAND_COOLANT_OFF);

    switch (tool.type) {
    case TOOL_WATER_JET:
      writeComment("Waterjet cutting.");
      break;
    case TOOL_LASER_CUTTER:
      writeComment("Laser cutting");
      break;
    case TOOL_PLASMA_CUTTER:
      writeComment("Plasma cutting");
      break;

    default:
      error(localize("The CNC does not support the required tool."));
      return;
    }
    writeln("");

    writeComment("tool.diameter = " + xyzFormat.format(tool.jetDiameter));
    writeln("");

    writeln("");
    writeln("FARCALL \"ATTENUATOR.PGM\" s$POWER");
    writeln("MSGCLEAR -1");
    writeln("MSGDISPLAY 1, \"Program Started\"");
    writeln("");

    writeln("REPEAT $OL_PASSES");

    if (tool.comment) {
      writeComment(tool.comment);
    }
    writeln("");
  }

/*
  // wcs
  if (insertToolCall) { // force work offset when changing tool
    currentWorkOffset = undefined;
  }
  var workOffset = currentSection.workOffset;
  if (workOffset == 0) {
    warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
    workOffset = 1;
  }
  if (workOffset > 0) {
    if (workOffset > 6) {
      var code = workOffset - 6;
      if (code > 3) {
        error(localize("Work offset out of range."));
        return;
      }
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(59) + "." + code);
        currentWorkOffset = workOffset;
      }
    } else {
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(53 + workOffset)); // G54->G59
        currentWorkOffset = workOffset;
      }
    }
  }
*/

  forceXYZ();

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

/*
  // set coolant after we have positioned at Z
  if (false) {
    var c = mapCoolantTable.lookup(tool.coolant);
    if (c) {
      writeBlock(mFormat.format(c));
    } else {
      warning(localize("Coolant not supported."));
    }
  }
*/

  forceAny();

  split = false;
  if (properties.useRetracts) {

    var initialPosition = getFramePosition(currentSection.getInitialPosition());

    if (insertToolCall || retracted) {
      gMotionModal.reset();

      if (!machineConfiguration.isHeadConfiguration()) {
        writeBlock(
          gAbsIncModal.format(90),
          gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y)
        );
      } else {
        writeBlock(
          gAbsIncModal.format(90),
          gMotionModal.format(0),
          xOutput.format(initialPosition.x),
          yOutput.format(initialPosition.y)
        );
      }
    } else {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0),
        xOutput.format(initialPosition.x),
        yOutput.format(initialPosition.y)
      );
    }
  } else {
    split = true;
  }
}

function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock(gFormat.format(4), "X" + secFormat.format(seconds));
}

function onCycle() {
  onError("Drilling is not supported by CNC.");
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

var shapeArea = 0;
var shapePerimeter = 0;
var shapeSide = "inner";
var cuttingSequence = "";

function onParameter(name, value) {
  if ((name == "action") && (value == "pierce")) {
    //writeComment("RUN POINT-PIERCE COMMAND HERE");
    writeln("REPEAT $IL_PASSES");
  } else if (name == "shapeArea") {
    shapeArea = value;
    writeComment("SHAPE AREA = " + xyzFormat.format(shapeArea));
  } else if (name == "shapePerimeter") {
    shapePerimeter = value;
    writeComment("SHAPE PERIMETER = " + xyzFormat.format(shapePerimeter));
  } else if (name == "shapeSide") {
    shapeSide = value;
    writeComment("SHAPE SIDE = " + value);
    writeln("");
  } else if (name == "beginSequence") {
    if (value == "piercing") {
      if (cuttingSequence != "piercing") {
        if (properties.allowHeadSwitches) {
          writeln("");
          writeComment("Switch to piercing head before continuing");
          onCommand(COMMAND_STOP);
          writeln("");
        }
      }
    } else if (value == "cutting") {
      if (cuttingSequence == "piercing") {
        if (properties.allowHeadSwitches) {
          writeln("");
          writeComment("Switch to cutting head before continuing");
          onCommand(COMMAND_STOP);
          writeln("");
        }
      }
    }
    cuttingSequence = value;
  }
}

var deviceOn = false;

function setDeviceMode(enable) {
  if (enable != deviceOn) {
    deviceOn = enable;
    if (enable) {
      writeln("BEAMON");
    } else {
      writeln("ENDRPT");
      writeln("BEAMOFF");
    }
  }
}

function onPower(power) {
  setDeviceMode(power);
}

function onRapid(_x, _y, _z) {

  if (!properties.useRetracts && ((movement == MOVEMENT_RAPID) || (movement == MOVEMENT_HIGH_FEED))) {
    doSplit();
    return;
  }

  if (split) {
    split = false;
    var start = getCurrentPosition();
    onRapid(start.x, start.y, start.z);
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  if (x || y) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(0), x, y);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {

  if (!properties.useRetracts && ((movement == MOVEMENT_RAPID) || (movement == MOVEMENT_HIGH_FEED))) {
    doSplit();
    return;
  }

  if (split) {
    resumeFromSplit(feed);
  }

  // at least one axis is required
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var f = "F$FEED";//feedOutput.format("$FEED");
  if (x || y) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        writeBlock(gFormat.format(41));
        writeBlock(gMotionModal.format(1), x, y, f);
        break;
      case RADIUS_COMPENSATION_RIGHT:
        writeBlock(gFormat.format(42));
        writeBlock(gMotionModal.format(1), x, y, f);
        break;
      default:
        writeBlock(gFormat.format(40));
        writeBlock(gMotionModal.format(1), x, y, f);
      }
    } else {
      writeBlock(gMotionModal.format(1), x, y, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function doSplit() {
  if (!split) {
    split = true;
    gMotionModal.reset();
    xOutput.reset();
    yOutput.reset();
    feedOutput.reset();
  }
}

function resumeFromSplit(feed) {
  if (split) {
    split = false;
    var start = getCurrentPosition();
    var _pendingRadiusCompensation = pendingRadiusCompensation;
    pendingRadiusCompensation = -1;
    onLinear(start.x, start.y, start.z, feed);
    pendingRadiusCompensation = _pendingRadiusCompensation;
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {

  if (!properties.useRetracts && ((movement == MOVEMENT_RAPID) || (movement == MOVEMENT_HIGH_FEED))) {
    doSplit();
    return;
  }

  // one of X/Y and I/J are required and likewise
  
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  if (split) {
    resumeFromSplit(feed);
  }

  var start = getCurrentPosition();
  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), "F$FEED");
      break;
    default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), "F$FEED");
      break;
    default:
      linearize(tolerance);
    }
  }
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  COMMAND_END:2
};

function onCommand(command) {
  switch (command) {
  case COMMAND_POWER_ON:
    return;
  case COMMAND_POWER_OFF:
    return;
  case COMMAND_COOLANT_ON:
    return;
  case COMMAND_COOLANT_OFF:
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  setDeviceMode(false);
  forceAny();
}

function onClose() {
  writeln("");

  writeln("ENDRPT");

  var x = xOutput.format(0);
  var y = yOutput.format(0);
  writeBlock(gMotionModal.format(0), x, y);
  writeln("MSGDISPLAY 1, \"Program Finished\"");
  writeBlock(gAbsIncModal.format(91));

  onCommand(COMMAND_COOLANT_OFF);

  onImpliedCommand(COMMAND_END);
  writeBlock(mFormat.format(02)); // stop program
}
