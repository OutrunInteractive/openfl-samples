package;

import lime.ui.Gamepad;
import lime.ui.GamepadButton;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.FPS;
import openfl.display.Sprite;
import openfl.display.Tile;
import openfl.display.Tilemap;
import openfl.display.Tileset;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.utils.Assets;
import openfl.Vector;
import openfl.filters.BlurFilter;
import openfl.filters.ColorMatrixFilter;
import openfl.display.GradientType;
import openfl.geom.Rectangle;

class Main extends Sprite
{
	private var addingBunnies:Bool;
	private var bunnies:Array<Bunny>;
	private var fps:FPS;
	private var gravity:Float;
	private var minX:Int;
	private var minY:Int;
	private var maxX:Int;
	private var maxY:Int;
	private var tileset:Tileset;
	#if (flash || use_tilemap)
	private var tilemap:Tilemap;
	#else
	private var indices:Vector<Int>;
	private var transforms:Vector<Float>;
	#end
	private var copyBitmapData:BitmapData;
	private var stageCopy:Bitmap;
	private var blurredCopy:Bitmap;
	private var blurredBitmapData:BitmapData;
	private var bottomRightCopy:Bitmap;
	private var bottomRightBitmapData:BitmapData;
	private var maskShape:Sprite;
	private var lowerMask:Sprite;
	private var leftTop:Sprite;
	private var leftWidth:Int;
	private var leftHeight:Int;
	private var bigBunny:Bitmap;

	public function new()
	{
		super();

		bunnies = new Array();

		minX = 0;
		maxX = Std.int(stage.stageWidth / 2);
		minY = 0;
		maxY = Std.int(stage.stageHeight / 2);
		gravity = 0.5;

		var bitmapData = Assets.getBitmapData("assets/wabbit_alpha.png");
		tileset = new Tileset(bitmapData);
		tileset.addRect(bitmapData.rect);

		// compute integer quadrant dimensions (avoid fractional pixels)
		leftWidth = Std.int(stage.stageWidth / 2);
		leftHeight = Std.int(stage.stageHeight / 2);

		// Container for the upper-left quadrant (make it a child of Main)
		leftTop = new Sprite();
		leftTop.x = 0;
		leftTop.y = 0;
		addChild(leftTop);

		// Create copy bitmap
		copyBitmapData = new BitmapData(leftWidth, leftHeight, true, 0);
		stageCopy = new Bitmap(copyBitmapData);
		stageCopy.x = leftWidth;
		stageCopy.y = 0; // Align to top
		addChild(stageCopy);
		copyBitmapData.disposeImage();

		// Initialize blurred copies (bottom-left 5x5, bottom-right 10x10)
		blurredBitmapData = new BitmapData(leftWidth, leftHeight, true, 0);
		blurredCopy = new Bitmap(blurredBitmapData);
		blurredCopy.x = 0;
		blurredCopy.y = leftHeight;
		blurredCopy.filters = [new BlurFilter(5, 5)];
		addChild(blurredCopy);
		blurredBitmapData.disposeImage();

		bottomRightBitmapData = new BitmapData(leftWidth, leftHeight, true, 0);
		bottomRightCopy = new Bitmap(bottomRightBitmapData);
		bottomRightCopy.x = leftWidth;
		bottomRightCopy.y = leftHeight;
		// blur + sepia color matrix
		bottomRightCopy.filters = [
			new BlurFilter(10, 10),
			new ColorMatrixFilter([
				0.393, 0.769, 0.189, 0, 0,
				0.349, 0.686, 0.168, 0, 0,
				0.272, 0.534, 0.131, 0, 0,
				    0,     0,     0, 1, 0
			])
		];
		addChild(bottomRightCopy);
		bottomRightBitmapData.disposeImage();

		// Create circular mask (upper-right)
		maskShape = new Sprite();
		maskShape.graphics.beginFill(0xFF0000);
		// center inside the integer quadrant and use integer radius
		maskShape.graphics.drawCircle(leftWidth / 2, leftHeight / 2, Std.int(Math.min(leftWidth, leftHeight) / 2));
		maskShape.graphics.endFill();
		// position mask over the upper-right quadrant (stageCopy)
		maskShape.x = leftWidth;
		maskShape.y = 0;
		addChild(maskShape);

		// Create circular mask for lower-left (apply to blurredCopy)
		lowerMask = new Sprite();
		lowerMask.graphics.beginFill(0xFF0000);
		lowerMask.graphics.drawCircle(leftWidth / 2, leftHeight / 2, Std.int(Math.min(leftWidth, leftHeight) / 2));
		lowerMask.graphics.endFill();
		// position mask over the lower-left quadrant
		lowerMask.x = 0;
		lowerMask.y = leftHeight;
		addChild(lowerMask);

		#if (flash || use_tilemap)
		tilemap = new Tilemap(leftWidth, leftHeight, tileset);
		tilemap.y = 0; // Align to top
		tilemap.tileAlphaEnabled = false;
		tilemap.tileBlendModeEnabled = false;
		tilemap.tileColorTransformEnabled = false;
		leftTop.addChild(tilemap);
		// leftTop.mask = maskShape;
		#else
		indices = new Vector<Int>();
		transforms = new Vector<Float>();
		// apply mask to the upper-right bitmap copy for non-tilemap builds
		stageCopy.mask = maskShape;
		#end

		// apply lower-left mask to the blurred bottom-left bitmap
		blurredCopy.mask = lowerMask;

		// Big bunny in front of bouncing bunnies (centered, 5x scale)
		bigBunny = new Bitmap(tileset.bitmapData);
		bigBunny.scaleX = 5.0;
		bigBunny.scaleY = 5.0;
		bigBunny.x = Std.int(leftWidth / 2 - (tileset.bitmapData.width * 5.0) / 2);
		bigBunny.y = Std.int(leftHeight / 2 - (tileset.bitmapData.height * 5.0) / 2);
		leftTop.addChild(bigBunny);

		// stageCopy remains unmasked (upper-right is free)

		#if !html5
		fps = new FPS();
		#if !hide_fps
		addChild(fps);
		#end
		#end

		stage.addEventListener(MouseEvent.MOUSE_DOWN, stage_onMouseDown);
		stage.addEventListener(MouseEvent.MOUSE_UP, stage_onMouseUp);
		stage.addEventListener(Event.ENTER_FRAME, stage_onEnterFrame);
		stage.addEventListener(Event.RESIZE, stage_onResize);

		Gamepad.onConnect.add(gamepad_onConnect);

		for (gamepad in Gamepad.devices)
		{
			gamepad_onConnect(gamepad);
		}

		var count = #if bunnies Std.parseInt(haxe.macro.Compiler.getDefine("bunnies")) #else 100 #end;

		for (i in 0...count)
		{
			addBunny();
		}
	}

	private function addBunny():Void
	{
		var bunny = new Bunny();
		bunny.x = 0;
		bunny.y = 0;
		bunny.speedX = Math.random() * 5;
		bunny.speedY = (Math.random() * 5) - 2.5;
		bunnies.push(bunny);

		#if (!flash && !use_tilemap)
		indices.push(bunny.id);
		transforms.push(0);
		transforms.push(0);
		#else
		tilemap.addTile(bunny);
		#end
	}

	// Event Handlers

	private function gamepad_onButtonDown(button:GamepadButton):Void
	{
		addingBunnies = true;
	}

	private function gamepad_onButtonUp(button:GamepadButton):Void
	{
		addingBunnies = false;
		trace(bunnies.length + " bunnies");
	}

	private function gamepad_onConnect(gamepad:Gamepad):Void
	{
		gamepad.onButtonDown.add(gamepad_onButtonDown);
		gamepad.onButtonUp.add(gamepad_onButtonUp);
	}

	private function drawGradient():Void
	{
		#if (!flash && !use_tilemap)
		leftTop.graphics.clear();
		var matrix = new openfl.geom.Matrix();
		matrix.createGradientBox(leftWidth, leftHeight, 0, 0, 0);
		leftTop.graphics.beginGradientFill(GradientType.LINEAR, [0xFF0000, 0x00FF00], // Red to Green
			[1, 1], // Alpha values
			[0, 255], // Ratio
			matrix);
		leftTop.graphics.drawRect(0, 0, leftWidth, leftHeight);
		leftTop.graphics.endFill();
		#end
	}

	private function stage_onEnterFrame(event:Event):Void
	{
		var bunny;

		drawGradient(); // Add gradient before drawing bunnies

		#if (!flash && !use_tilemap)
		// Draw bunnies directly without white background
		leftTop.graphics.beginBitmapFill(tileset.bitmapData, null, false);
		leftTop.graphics.drawQuads(tileset.rectData, indices, transforms);
		#end

		for (i in 0...bunnies.length)
		{
			bunny = bunnies[i];

			bunny.x += bunny.speedX;
			bunny.y += bunny.speedY;
			bunny.speedY += gravity;

			if (bunny.x > maxX)
			{
				bunny.speedX *= -1;
				bunny.x = maxX;
			}
			else if (bunny.x < minX)
			{
				bunny.speedX *= -1;
				bunny.x = minX;
			}

			if (bunny.y > maxY)
			{
				bunny.speedY *= -0.8;
				bunny.y = maxY;

				if (Math.random() > 0.5)
				{
					bunny.speedY -= 3 + Math.random() * 4;
				}
			}
			else if (bunny.y < minY)
			{
				bunny.speedY = 0;
				bunny.y = minY;
			}

			#if (!flash && !use_tilemap)
			transforms[i * 2] = bunny.x;
			transforms[i * 2 + 1] = bunny.y;
			#end
		}

		#if (!flash && !use_tilemap)
		// Draw the non-tilemap content into the leftTop container instead of Main
		// leftTop.graphics.clear();
		// leftTop.graphics.beginBitmapFill(tileset.bitmapData, null, false);
		// leftTop.graphics.drawQuads(tileset.rectData, indices, transforms);
		#end

		// Copy the left half to the right half (draw the leftTop container)
		copyBitmapData.draw(leftTop, null, null, null, null, true);

		// Update blurred copy
		blurredBitmapData.draw(leftTop, null, null, null, null, true);

		// Update bottom-right blurred copy (10x10)
		bottomRightBitmapData.draw(leftTop, null, null, null, null, true);

		if (addingBunnies)
		{
			#if hide_fps
			trace(fps.currentFPS);
			#end

			for (i in 0...100)
			{
				addBunny();
			}
		}
	}

	private function stage_onMouseDown(event:MouseEvent):Void
	{
		addingBunnies = true;
	}

	private function stage_onMouseUp(event:MouseEvent):Void
	{
		addingBunnies = false;
		trace(bunnies.length + " bunnies");
	}

	private function stage_onResize(event:Event):Void
	{
		// recompute integer quadrant dims to avoid bleed/overflow
		leftWidth = Std.int(stage.stageWidth / 2);
		leftHeight = Std.int(stage.stageHeight / 2);
		maxX = leftWidth;
		maxY = leftHeight;

		// Update mask
		maskShape.graphics.clear();
		maskShape.graphics.beginFill(0xFF0000);
		maskShape.graphics.drawCircle(leftWidth / 2, leftHeight / 2, Std.int(Math.min(leftWidth, leftHeight) / 2));
		maskShape.graphics.endFill();
		// keep mask positioned over the upper-right quadrant
		maskShape.x = leftWidth;
		maskShape.y = 0;

		// Update copy bitmap
		copyBitmapData.dispose();
		copyBitmapData = new BitmapData(leftWidth, leftHeight, true, 0);
		stageCopy.bitmapData = copyBitmapData;
		stageCopy.x = leftWidth;
		stageCopy.y = 0;

		// Update blurred copy
		blurredBitmapData.dispose();
		blurredBitmapData = new BitmapData(leftWidth, leftHeight, true, 0);
		blurredCopy.bitmapData = blurredBitmapData;
		blurredCopy.x = 0;
		blurredCopy.y = leftHeight;

		// Update bottom-right blurred copy
		bottomRightBitmapData.dispose();
		bottomRightBitmapData = new BitmapData(leftWidth, leftHeight, true, 0);
		bottomRightCopy.bitmapData = bottomRightBitmapData;
		bottomRightCopy.x = leftWidth;
		bottomRightCopy.y = leftHeight;

		#if (flash || use_tilemap)
		tilemap.width = leftWidth;
		tilemap.height = leftHeight;
		tilemap.y = 0; // Keep aligned to top
		#end
		// redraw gradient to match new integer dims
		drawGradient();

		// reposition big bunny to remain centered in the upper-left quadrant
		if (bigBunny != null)
		{
			bigBunny.x = Std.int(leftWidth / 2 - (tileset.bitmapData.width * 5.0) / 2);
			bigBunny.y = Std.int(leftHeight / 2 - (tileset.bitmapData.height * 5.0) / 2);
		}
	}
}
